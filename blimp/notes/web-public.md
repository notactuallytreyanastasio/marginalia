# Marginalia public pages: specification

Scope: the pages a stranger can open without an account, plus the shared layout, components, auth plugs and error pages they depend on. Everything here was read from `lib/marginalia_web/` (Phoenix 1.8.14, LiveView 1.2.11, Elixir). Class names are exact; the stylesheet (`assets/css/app.css`, plus one inline `<style>` on the landing page) is reused unchanged, so a rewrite must emit the same class names on the same elements.

Verbatim extracts that are too long to inline sit next to this file in `blimp/notes/web-public-extracts/`:

| file | content |
|---|---|
| `landing.css` | the landing page's inline `<style>` block, 307 lines, dedented |
| `landing-body.heex` | the landing page's whole markup (the `<div id="landing">` element), 1018 lines, dedented |
| `landing-reveal-hook.js` | the `.Reveal` hook |

HEEx quoted below is dedented, and `~H"""` lines are omitted. Outside the extracts, "quoted" means copied from the source with whitespace preserved.

## 0. Conventions that apply to every page

**LiveView lifecycle.** Every page except `/sitemap.xml` is a LiveView. Each is rendered twice: once on the HTTP GET (static render, `connected?` false), then again over the websocket (`/live`). `mount` runs on both, so every data load below happens twice per visit. A `push_navigate` from `mount` during the static render becomes an HTTP 302 with the flash carried in the session cookie.

**Not-found pattern.** All the show pages do the same thing when the lookup returns nil: `put_flash(:error, "<message>")` and `push_navigate(to: <index page>)`. The messages and targets are listed per page. The flash is rendered by `Layouts.app`'s `flash_group` on the destination page.

**Stale-bundle reload (`MarginaliaWeb.Freshness`).** `use MarginaliaWeb, :live_view` adds `on_mount MarginaliaWeb.Freshness` to every LiveView. When the socket is connected and `static_changed?` is true (the `phx-track-static` asset URLs the page was rendered with differ from what the server now serves), it attaches a `handle_params` hook. On the next `handle_params`, if the params lack `"_fresh"`, it halts with `redirect(socket, external: uri)` where `uri` has query `_fresh=1` merged into the existing query (decoded, `Map.put`, re-encoded). A page that already has `_fresh` is left alone (the fuse against an infinite loop through a caching proxy). In effect: a tab left open across a deploy does a full browser reload to the same URL plus `?_fresh=1`.

**Caching.** `Marginalia.Cache` is an ETS table, per node, default TTL 5 minutes. Used by: `Cases.published/0` (key `:published_cases`), `Links.public_links/0` (key `:public_links`), the sitemap (key `:sitemap`, TTL 30 minutes). Writers invalidate keys when links, edges or collections change. Nothing here is per-viewer.

**"The owner".** Every public listing is the content of one account: the user whose email equals the `:owner_email` app env (`OWNER_EMAIL` env var, default `bobbbygrayson@gmail.com`), compared case-insensitively (`Accounts.owner/0` does `lower(email) == lower(owner_email)`; returns nil when the env is empty or no such user). When there is no owner, `Cases.published/0`, `Works.public_drafts/0`, `Works.public_draft/1`, `Links.public_links/0` and `Links.public_link/1` return `[]`/`[]`/nil/`[]`/nil. `Folders.published/0` does not use the owner: it returns every folder with a `published_at`.

**Markdown.** `Marginalia.Markdown.to_html(text, breaks: :hard | :soft)` is MDEx (comrak) with extensions strikethrough, table, autolink, tasklist, footnotes; `parse.smart` false; `render.hardbreaks` true only for `:hard` (the default, used for model replies and story prose); `render.unsafe` false; ammonia sanitising with MDEx's default sanitize options. `nil` and `""` give empty output; non-binary input is HTML-escaped `to_string`. A parse failure falls back to HTML-escaped plain text. Drafts are rendered with `breaks: :soft` (a newline inside a paragraph is a space).

**Title pluralisation, numbers.** Helper conventions repeated in several pages are defined where they first appear.

## 1. Routes in scope

From `router.ex`. Pipelines:

* `:browser`: `accepts ["html"]`, `fetch_session`, `fetch_live_flash`, `put_root_layout html: {Layouts, :root}`, `protect_from_forgery`, `put_secure_browser_headers`, `fetch_current_scope_for_user`.
* `:bare_browser`: identical except the root layout is `{Layouts, :bare}`.

| path | module / action | pipeline | live_session (`on_mount`) | auth level |
|---|---|---|---|---|
| `GET /` | `LandingLive` `:index` | `:bare_browser` | `:landing` (`UserAuth :mount_current_scope`) | public, no guest minted |
| `GET /sitemap.xml` | `SitemapController.index` | `:browser` | none (controller) | public |
| `/cases` | `CaseLive.Index` `:index` | `:browser` | `:cases` (`:mount_current_scope`) | public |
| `/cases/:slug` | `CaseLive.Show` `:show` | same | same | public |
| `/cases/:slug/read` | `CaseLive.Read` `:read` | same | same | public |
| `/cases/:slug/read/:lead` | `CaseLive.Read` `:read` | same | same | public |
| `/drafts` | `DraftLive.Index` | same | same | public |
| `/drafts/:slug` | `DraftLive.Show` | same | same | public |
| `/drafts/:slug/changes` | `DraftLive.Changes` | same | same | public |
| `/linked` | `LinkedLive.Index` | same | same | public |
| `/linked/:id` | `LinkedLive.Show` | same | same | public |
| `/reading` | `ReadingLive.Index` | same | same | public |
| `/reading/:slug` | `ReadingLive.Story` | same | same | public |
| `/reading/:slug/:ordinal` | `ReadingLive.Step` | same | same | public |

Every page except the landing page uses the root layout `root.html.heex` and wraps its content in `Layouts.app`. The landing page uses `bare.html.heex` and does not use `Layouts.app` at all (so it has no app header and, notably, no `flash_group`).

Routes outside the scope that these pages link to (documented elsewhere): `/works/new`, `/works/:slug` (the `:allow_guest` session, which mints a guest), `/links/:id?lead=:slug` (the pairwise reading), `/import`, `/users/log-in`, `/users/register`, `/users/settings`, `/users/log-out`, `/works`, `/links`, `/cuts`, `/stacks`, `/stacks/:id`.

No public route is behind `ensure_user_or_guest` or `require_real_account`. The router comment gives the reason: minting a guest user row for every visitor had produced 762 `users` rows for five real uploaders. Anything that remembers something about an anonymous visitor (the tour having been seen) uses `localStorage`.

Dynamic params are all strings. `:slug` for cases is `Cases.slug(name)`: downcase, replace runs of `[^a-z0-9]` (unicode-aware regex `~r/[^a-z0-9]+/u`) with `-`, trim `-`. `:slug` for drafts is the work's 22-character URL-safe base64 slug (128 random bits, no padding). `:slug` for readings is the folder's slug (`Folders.mint_slug`: name downcased, runs of non-`[a-z0-9]` to `-`, trimmed of `-`, first 60 chars, `stack` if empty; if that slug is taken, `-` plus 3 random bytes url-base64 is appended). `:id` for `/linked/:id` is a link's integer id, looked up with `Repo.get(Link, id)` (a non-integer raises `Ecto.Query.CastError`, which Phoenix renders as 400). `:ordinal` is parsed with `Integer.parse`, and trailing garbage means not found.

## 2. Identity and session (`user_auth.ex`)

### 2.1 Who is who

| visitor kind | how recognised | `current_scope` |
|---|---|---|
| anonymous visitor | no valid `user_token` in the session and no valid remember-me cookie | `nil` (note: `Scope.for_user(nil)` returns `nil`, not a struct) |
| guest | a `users` row with `is_guest = true`, email `guest-<22 url-safe-base64 chars>@guest.marginalia.local`, random 32-byte password (hashed), `confirmed_at` now | `%Scope{user: user}` |
| real user | `users` row with `is_guest = false` | `%Scope{user: user}` |
| owner | a real user whose email equals `OWNER_EMAIL` (case-insensitive) | `%Scope{user: user}`; `Accounts.owner?/1` |
| admin | `users.is_admin` boolean column exists (default false). Nothing in the files in scope reads it. Privilege is decided by owner email, not by this column. | n/a |

The `current_scope` assign is what templates test. `Layouts.app` checks `@current_scope && @current_scope.user && @current_scope.user.is_guest`. The landing page tests `@current_scope` alone, which is truthy for guests and real users.

### 2.2 Cookies and session keys

Endpoint session (`endpoint.ex`): `Plug.Session`, `store: :cookie`, cookie name `_marginalia_key`, `signing_salt: "ZFoSjTaR"`, `same_site: "Lax"`. Signed, not encrypted; no `max_age`, so it is a browser-session cookie. The websocket gets the same session via `connect_info: [session: @session_options]` on `/live`.

Every HTML page response writes this cookie, because `root.html.heex` calls `get_csrf_token()`, which puts `_csrf_token` in the session. A visitor who has only read public pages therefore holds a cookie containing a CSRF token and nothing else.

Session keys (strings in the session, atoms in the plugs):

| key | value | written by |
|---|---|---|
| `user_token` | the raw 32-byte token binary | `put_token_in_session` |
| `live_socket_id` | `"users_sessions:" <> Base.url_encode64(token)` (padded url-safe base64) | `put_token_in_session` |
| `user_remember_me` | `true` | `write_remember_me_cookie`, or when a token is restored from the remember-me cookie |
| `user_return_to` | the request path of the denied GET | `maybe_store_return_to` (GET only; `current_path(conn)`) |
| `_csrf_token`, flash | Phoenix | Phoenix |

Remember-me cookie: name `_marginalia_web_user_remember_me`; options `sign: true`, `max_age: 14 * 24 * 60 * 60` (1,209,600 s), `same_site: "Lax"`; value is the same raw token. Written when the login params contain `"remember_me" => "true"`, or when the session already has `user_remember_me == true` (so a token reissue keeps the cookie fresh). Deleted with the same options on logout.

### 2.3 Tokens (`Accounts`, `UserToken`)

* `Accounts.generate_user_session_token(user)`: `UserToken.build_session_token`: 32 bytes from `:crypto.strong_rand_bytes`, stored unhashed in `users_tokens.token` with `context = "session"`, `user_id`, `authenticated_at = user.authenticated_at || now(seconds)`. Inserted with `Repo.insert!`. Returns the raw token.
* `Accounts.get_user_by_session_token(token)`: joins `users_tokens` on token and context `"session"`, requires `inserted_at > now - 14 days`, returns `{user_with_authenticated_at_set_from_token, token.inserted_at}` or nil.
* `Accounts.delete_user_session_token(token)`: deletes the rows with that token and context `"session"`.
* `Accounts.create_guest_user/0`: inserts a user from `email_changeset(..., validate_unique: false)` with the generated email, a `password_changeset` with a random 32-byte password (url-safe base64, no padding), `confirmed_at = now(seconds)`, `is_guest = true`. Returns `{:ok, user}` or `{:error, changeset}`.
* `Accounts.sudo_mode?(user, minutes \\ -20)`: `user.authenticated_at` is after `now + minutes minutes`; false when `authenticated_at` is not a DateTime.

### 2.4 The `:browser` plug `fetch_current_scope_for_user`

1. `ensure_user_token`: if the session has `user_token`, use it. Otherwise `fetch_cookies(signed: [remember_cookie])`; if the remember-me cookie is present and verifies, put its value into the session (`user_token`, `live_socket_id`) and set `user_remember_me = true`. Otherwise no token.
2. With a token, `Accounts.get_user_by_session_token`. On a hit: `assign(:current_scope, Scope.for_user(user))`, then `maybe_reissue_user_session_token`: if `DateTime.diff(now, token_inserted_at, :day) >= 7`, run `create_or_extend_session(conn, user, %{})` (new token row inserted, session token replaced, remember-me cookie rewritten when `user_remember_me` is set). The old token row is not deleted; it ages out at 14 days.
3. No token, or a token that matches nothing (expired, deleted): `assign(:current_scope, nil)`. The stale `user_token` is left in the session.

`create_or_extend_session(conn, user, params)`: generates a token, reads `user_remember_me`, calls `renew_session(conn, user)`, stores the token, then possibly writes the remember-me cookie. `renew_session` is a no-op when `conn.assigns.current_scope.user.id == user.id` (already logged in as that user: avoids CSRF failures in other open tabs). Otherwise it does `delete_csrf_token()`, `configure_session(renew: true)`, `clear_session()` (session-fixation defence).

### 2.5 Login and logout (called by `UserSessionController`)

* `log_in_user(conn, user, params)`: reads `:user_return_to` from the session first, then `create_or_extend_session`, deletes `:user_return_to`, redirects to `user_return_to` or `signed_in_path(conn)`. `signed_in_path` is `/users/settings` if the conn's `current_scope` already holds a `%User{}` (the scope assigned before the login), else `/`.
* `log_out_user(conn)`: deletes the session token row, broadcasts `"disconnect"` on `live_socket_id` so open LiveViews drop, `renew_session(conn, nil)` (clears the session), deletes the remember-me cookie, redirects to `/`.
* `disconnect_sessions(tokens)`: broadcasts `"disconnect"` for each `users_sessions:<b64 token>` topic. Used after a password change.

### 2.6 Guest minting: `ensure_user_or_guest` (plug)

Applies only to the router scope containing `/works/*`, `/import`, `/stacks/*`, `/cuts/*`, `/links/*` and `POST /works/new`, `GET /works/:id/graph.json|graph.dot|trace.json`. **Not** to anything in this document. If `current_scope.user` exists it does nothing. Otherwise it calls `Accounts.create_guest_user/0`; on `{:ok, guest}` it runs `create_or_extend_session(conn, guest, %{})` (so a guest gets a session token, `live_socket_id`, and since `user_remember_me` is unset, no remember-me cookie, so a guest lives and dies with the browser session cookie) and assigns `Scope.for_user(guest)`. On `{:error, reason}` it logs `marginalia: could not create a guest account: <inspect reason>`, sets flash error `"Something went wrong. Try logging in."`, redirects to `/users/log-in` and halts.

### 2.7 `require_real_account` (plug) and the `on_mount` hooks

| name | when | outcome |
|---|---|---|
| plug `require_real_account` | `current_scope.user` nil | flash error `"You must log in to access this page."`, store `user_return_to` (GET), redirect `/users/log-in`, halt |
| | user is guest | flash info `"Create an account to keep your drafts."`, redirect `/users/register`, halt |
| | else | continue |
| plug `require_authenticated_user` | no user | as the nil case above |
| `on_mount :mount_current_scope` | always | assigns `current_scope` via `assign_new`, from `session["user_token"]` only (the remember-me cookie is not consulted here; the plug already copied it into the session). Never redirects. Used by every page in this document. |
| `on_mount :require_authenticated` | no user | flash error `"You must log in to access this page."`, redirect `/users/log-in`, halt |
| `on_mount :allow_guest` | no user | redirect `/users/log-in` (no flash), halt |
| `on_mount :require_real_account` | no user | redirect `/users/log-in`, halt |
| | guest | flash info `"Create an account to keep your drafts."`, redirect `/users/register`, halt |
| `on_mount :require_sudo_mode` | `Accounts.sudo_mode?(user, -10)` false | flash error `"You must re-authenticate to access this page."`, redirect `/users/log-in`, halt (raises if `current_scope` is nil: it dereferences `.user`) |

`mount_current_scope`: when the token is missing or `get_user_by_session_token` returns nil, the scope is nil.

## 3. Layouts

### 3.1 `root.html.heex` and `bare.html.heex`

They are byte-identical except the body. Both:

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
    <script> ...theme script, below... </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

`root`'s body is exactly `{@inner_content}` (preceded by a HEEx comment that renders nothing). `bare`'s body is also exactly `{@inner_content}`. In practice the two differ only by name. The "bare" distinction exists so the landing page gets no auth menu; since the app header lives in `Layouts.app` (not in the root layout), the two roots render the same.

`~p"/assets/css/app.css"` and `~p"/assets/js/app.js"` are static paths (`static_paths`: `assets fonts images favicon.ico robots.txt`). A rewrite should serve cache-busted URLs for both and keep `phx-track-static` on both tags, since the Freshness mechanism above depends on it.

The theme script (inline, in both):

```js
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
```

`Layouts.theme_toggle/1` (the button that dispatches `phx:set-theme`) exists but no page in this scope renders it, and `Layouts.app` does not include it. So nothing in the public UI lets a visitor change theme; the stored value is only read.

`app.js` (not in scope, but it determines behaviour): imports `phoenix_html`, `phoenix`, `phoenix_live_view`, the colocated hooks bundle (`phoenix-colocated/marginalia`, every `<script :type={ColocatedHook}>` in every module), and `topbar`. `new LiveSocket("/live", Socket, {longPollFallbackMs: 2500, params: {_csrf_token}, hooks: {...colocatedHooks}})`. `topbar` is shown on `phx:page-loading-start` (300 ms delay) and hidden on `phx:page-loading-stop`; bar colour `#29d`, shadow `rgba(0, 0, 0, .3)`. There is no custom JS for the reading rail: see the DraftLive.Show note.

### 3.2 `Layouts.head_meta/1`

Attrs (all optional strings, default nil): `page_title`, `page_description`, `page_robots`, `page_image`, `page_image_alt`, `page_url`.

Constants:

* tagline: `Someone who has actually read the whole thing`
* pitch (default description): `Upload a draft. It reads end to end, maps what's on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences.`
* default image alt: `Marginalia, a reader for drafts. A note in the margin reads: your opening promises a book about grief, chapter nine is the best thing here, and it belongs to a different one.`

Derived: `title = page_title || tagline`; `description = page_description || pitch`; `image = absolute(page_image || "/images/og.png")`; `image_alt = page_image_alt || default alt`; `canonical = absolute(page_url || "/")`. `absolute(v)` returns `v` unchanged if it starts with `http`, else `Endpoint.url() <> v`.

Output, in order:

```heex
<.live_title default={@tagline} suffix=" · Marginalia" phx-no-format>{@page_title}</.live_title>

<meta :if={@page_robots} name="robots" content={@page_robots} />
<meta name="description" content={@description} />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="Marginalia" />
<meta property="og:title" content={@title} />
<meta property="og:description" content={@description} />
<meta property="og:url" content={@canonical} />
<link rel="canonical" href={@canonical} />
<meta property="og:image" content={@image} />
<meta property="og:image:width" content="2400" />
<meta property="og:image:height" content="1260" />
<meta property="og:image:alt" content={@image_alt} />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content={@title} />
<meta name="twitter:description" content={@description} />
<meta name="twitter:image" content={@image} />
<meta name="theme-color" content="#fbfaf7" />
```

`live_title` renders `<title data-default="Someone who has actually read the whole thing" data-suffix=" · Marginalia">{page_title or default}{suffix}</title>`. The suffix is appended to the default too, so the landing page's title is `Someone who has actually read the whole thing · Marginalia`. (`data-prefix` is absent because no prefix is passed.) LiveView's client rewrites the title on navigation using those data attributes. Note `og:title` and `twitter:title` carry the bare title with no suffix.

The static card images are `priv/static/images/og.png` (site) and `priv/static/images/og-cases.png` (used by all three case pages), 2400x1260. The `robots` meta is only emitted when a page sets `page_robots`; pages that set it use `"index, follow"`. No page sets `noindex` (the 404/500 pages do, see section 5).

### 3.3 `Layouts.app/1`

Attrs: `flash` (map, required), `current_scope` (default nil), `bleed` (boolean, default false), slot `inner_block` (required). Full source:

```heex
<header class="mg-bar">
  <a href="/" class="mg-brand">Marginalia <span>a reader for drafts</span></a>
  <nav>
    <.link navigate={~p"/cases"}>Cases</.link>

    <%= cond do %>
      <% @current_scope && @current_scope.user && @current_scope.user.is_guest -> %>
        <.link navigate={~p"/works"}>Drafts</.link>
        <.link navigate={~p"/works/new"}>New draft</.link>
        <span class="text-[var(--mg-dim)] opacity-70">guest</span>
        <.link navigate={~p"/users/register"} class="mg-btn sm">Keep my drafts</.link>
      <% @current_scope && @current_scope.user -> %>
        <.link navigate={~p"/works"}>Drafts</.link>
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

<main class={if @bleed, do: "", else: "px-4 py-8 sm:px-6 lg:px-8"}>
  <div class="space-y-4">
    {render_slot(@inner_block)}
  </div>
</main>

<.flash_group flash={@flash} />
```

(The source also has HEEx and HTML comments, which render nothing or an HTML comment; the one HTML comment `<!-- The generated layout pinned every page inside max-w-2xl ... -->` before `<main>` is emitted into the page as a comment, harmless.)

Notes:

* The brand is a plain `<a href="/">` (full page load), the rest are `.link navigate` (live navigation: `<a href data-phx-link="redirect" data-phx-link-state="push">`).
* The three states of the nav: anonymous gets `Cases`, `Log in`. Guest gets `Cases`, `Drafts`, `New draft`, the dim word `guest`, and the `mg-btn sm` button `Keep my drafts` to `/users/register`. A real user gets `Cases`, `Drafts` (`/works`), `Linked` (`/links`), `Cuts` (`/cuts`), `Methods` (`/stacks`), `New draft`, their email (to `/users/settings`), and `Log out`. There is no separate admin or owner state.
* `Log out` is `<a href="/users/log-out" data-method="delete" data-csrf="..." data-to="/users/log-out">`. `phoenix_html` JS turns the click into a form submit with `_method=delete`.
* The public pages call `Layouts.app` with `current_scope={@current_scope}`. For an anonymous visitor that is nil, so they see `Cases` and `Log in`. There is no "Drafts" / "Linked" / "Readings" link in the header for anonymous visitors; those pages are reached from other pages and the sitemap.
* `bleed` is true only on `CaseLive.Read`: `<main class="">` and no padding.

### 3.4 `Layouts.flash_group/1`

Attrs: `flash` (required), `id` (default `"flash-group"`).

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

Behaviour: the two connection-state toasts are `hidden` until LiveView adds `phx-client-error` / `phx-server-error` to `<body>`-level containers and fires `phx-disconnected`. gettext strings are English literals (no other locale is configured in scope).

### 3.5 `Layouts.theme_toggle/1` (unused by public pages)

A pill with three buttons (`data-phx-theme="system" | "light" | "dark"`, each `phx-click={JS.dispatch("phx:set-theme")}`) and a sliding thumb. Classes: container `card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full`; thumb `absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]`; buttons `flex p-2 cursor-pointer w-1/3` containing icons `hero-computer-desktop-micro`, `hero-sun-micro`, `hero-moon-micro`, each `size-4 opacity-75 hover:opacity-100`.

## 4. Core components (`core_components.ex`)

Imported into every LiveView and function component module. Only `flash`, `icon`, `show`, `hide` are used by the files in this scope; the rest are documented because other scopes use them.

### `flash/1`

Attrs: `id` (string; defaults to `"flash-<kind>"`), `flash` (map, default `%{}`), `title` (default nil), `kind` (`:info | :error`, required), `rest` (global attrs). Slot: `inner_block`.

```heex
<div
  :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
  id={@id}
  phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
  role="alert"
  class="toast toast-top toast-end z-50"
  {@rest}
>
  <div class={[
    "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
    @kind == :info && "alert-info",
    @kind == :error && "alert-error"
  ]}>
    <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
    <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
    <div>
      <p :if={@title} class="font-semibold">{@title}</p>
      <p>{msg}</p>
    </div>
    <div class="flex-1" />
    <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
      <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
    </button>
  </div>
</div>
```

Rendered only if the slot or the flash has content. Click anywhere on it pushes `lv:clear-flash` (a built-in LiveView event) and hides it.

### `button/1`

Attrs: `rest` (global, extra allowed: `href navigate patch method download name value disabled`), `class` (any; default `["btn", variant_class]`), `variant` (`"primary"`), slot `inner_block` required. Variant map: `"primary"` gives `mg-btn`, nil gives `mg-btn ghost`. So the default class list is `["btn", "mg-btn ghost"]` and with `variant="primary"` it is `["btn", "mg-btn"]`. If `rest` has `href`, `navigate` or `patch` it renders `<.link class={@class} {@rest}>…</.link>`, else `<button class={@class} {@rest}>…</button>`.

### `input/1`

Attrs: `id` (default nil), `name`, `label` (string, nil), `value`, `type` (default `"text"`; values `checkbox color date datetime-local email file month number password search select tel text textarea time url week hidden`), `field` (a form field; when given: errors are shown only if `used_input?`, `id` defaults to the field id, `name` to `field.name` (plus `[]` if `multiple`), `value` to `field.value`), `errors` (list), `checked`, `prompt`, `options`, `multiple` (false), `class`, `error_class`, `rest` (global incl. `accept autocomplete capture cols disabled form list max maxlength min minlength multiple pattern placeholder readonly required rows size step`). Errors go through `translate_error/1` (gettext domain `errors`, with `count` plural support).

Variants:

```heex
<%!-- hidden --%>
<input type="hidden" id={@id} name={@name} value={@value} {@rest} />

<%!-- checkbox --%>
<div class="mg-field">
  <label for={@id}>
    <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} form={@rest[:form]} />
    <span class="label">
      <input type="checkbox" id={@id} name={@name} value="true" checked={@checked}
        class={@class || "checkbox checkbox-sm"} {@rest} />{@label}
    </span>
  </label>
  <.error :for={msg <- @errors}>{msg}</.error>
</div>

<%!-- select --%>
<div class="mg-field">
  <label for={@id}>
    <span :if={@label} class="mg-label block mb-1.5">{@label}</span>
    <select id={@id} name={@name}
      class={[@class || "mg-select", @errors != [] && "border-[var(--mg-accent)]"]}
      multiple={@multiple} {@rest}>
      <option :if={@prompt} value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, @value)}
    </select>
  </label>
  <.error :for={msg <- @errors}>{msg}</.error>
</div>

<%!-- textarea --%>
<div class="mg-field">
  <label for={@id}>
    <span :if={@label} class="mg-label block mb-1.5">{@label}</span>
    <textarea id={@id} name={@name}
      class={[@class || "mg-textarea", @errors != [] && "border-[var(--mg-accent)]"]}
      {@rest}>{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
  </label>
  <.error :for={msg <- @errors}>{msg}</.error>
</div>

<%!-- every other type --%>
<div class="mg-field">
  <label for={@id}>
    <span :if={@label} class="mg-label block mb-1.5">{@label}</span>
    <input type={@type} name={@name} id={@id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      class={[@class || "mg-input", @errors != [] && "border-[var(--mg-accent)]"]}
      {@rest} />
  </label>
  <.error :for={msg <- @errors}>{msg}</.error>
</div>
```

The private `error/1`: `<p class="mt-1.5 flex gap-2 items-center text-sm text-error"><.icon name="hero-exclamation-circle" class="size-5" />{message}</p>`. The `checked` default for a checkbox is `Phoenix.HTML.Form.normalize_value("checkbox", value)`.

### `header/1`

Slots: `inner_block` required, `subtitle`, `actions`.

```heex
<header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
  <div>
    <h1 class="text-lg font-semibold leading-8">{render_slot(@inner_block)}</h1>
    <p :if={@subtitle != []} class="text-sm text-base-content/70">{render_slot(@subtitle)}</p>
  </div>
  <div class="flex-none">{render_slot(@actions)}</div>
</header>
```

### `table/1`

Attrs: `id` (required), `rows` (required; may be a LiveStream), `row_id` (fn; defaults to `fn {id, _item} -> id end` for streams), `row_click` (fn), `row_item` (fn, default identity). Slots: `col` (required; attr `label`), `action`.

```heex
<table class="table table-zebra">
  <thead>
    <tr>
      <th :for={col <- @col}>{col[:label]}</th>
      <th :if={@action != []}><span class="sr-only">{gettext("Actions")}</span></th>
    </tr>
  </thead>
  <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
    <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
      <td :for={col <- @col} phx-click={@row_click && @row_click.(row)}
          class={@row_click && "hover:cursor-pointer"}>
        {render_slot(col, @row_item.(row))}
      </td>
      <td :if={@action != []} class="w-0 font-semibold">
        <div class="flex gap-4">
          <%= for action <- @action do %>{render_slot(action, @row_item.(row))}<% end %>
        </div>
      </td>
    </tr>
  </tbody>
</table>
```

### `list/1`

Slot `item` (required; attr `title` required).

```heex
<ul class="list">
  <li :for={item <- @item} class="list-row">
    <div class="list-col-grow">
      <div class="font-bold">{item.title}</div>
      <div>{render_slot(item)}</div>
    </div>
  </li>
</ul>
```

### `icon/1`

Attrs: `name` (required, must start with `hero-`), `class` (default `"size-4"`). Renders `<span class={[@name, @class]} />`. The icon is a CSS mask supplied by the Tailwind heroicons plugin from the class name (`hero-x-mark`, `hero-sun-micro`, ...). Icons used by files in scope: `hero-information-circle`, `hero-exclamation-circle`, `hero-x-mark`, `hero-arrow-path`, `hero-computer-desktop-micro`, `hero-sun-micro`, `hero-moon-micro`.

### JS helpers

`show(js \\ %JS{}, selector)`: `JS.show(to: selector, time: 300, transition: {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95", "opacity-100 translate-y-0 sm:scale-100"})`.
`hide(js \\ %JS{}, selector)`: `JS.hide(to: selector, time: 200, transition: {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"})`.
`translate_error({msg, opts})` and `translate_errors(errors, field)`: gettext in domain `errors`.

## 5. Error pages and the sitemap

### `ErrorHTML` (HTML errors)

`render("404.html")` and `render("500.html")` return a complete, self-contained document (no layout, no session, no assigns beyond the two strings); any other template returns the plain status message (`Phoenix.Controller.status_message_from_template`, e.g. `"Forbidden"`). `ErrorJSON.render(template, _)` returns `%{errors: %{detail: "<status message>"}}` (so `404.json` gives `{"errors":{"detail":"Not Found"}}`). `page_html.ex` is an empty file (no module, no templates).

| status | h1 | paragraph |
|---|---|---|
| 404 | `Nothing at that address` | `The link may be old, or the draft may have been taken down. Nothing is lost by following a wrong address.` |
| 500 | `Something broke` | `That is this end, not yours, and it has been logged. Trying again in a moment is worth doing — most of what breaks here is transient.` |

Document:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="robots" content="noindex" />
    <title>{@heading} · Marginalia</title>
    <style>
      :root{color-scheme:light dark}
      body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
        background:#fbfaf7;color:#1c1a17;
        font-family:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif}
      main{max-width:32rem;padding:2rem 1.5rem}
      h1{font-size:1.5rem;font-weight:600;margin:0 0 .6rem;letter-spacing:-.01em}
      p{margin:0 0 1.2rem;line-height:1.65;color:#6b665e}
      nav{display:flex;gap:1rem;flex-wrap:wrap;font-size:.85rem;
        font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
      a{color:#8a3324;text-decoration:none;border-bottom:1px solid #e0dbd2;padding-bottom:1px}
      a:hover{border-bottom-color:#8a3324}
      @media (prefers-color-scheme:dark){
        body{background:#16150f;color:#e9e4d9}
        p{color:#a49e91}
        a{color:#e0a48a;border-bottom-color:#2e2b24}
      }
    </style>
  </head>
  <body>
    <main>
      <h1>{@heading}</h1>
      <p>{@body}</p>
      <nav>
        <a href="/">Marginalia</a>
        <a href="/cases">Cases</a>
        <a href="/drafts">Drafts</a>
        <a href="/reading">Readings</a>
      </nav>
    </main>
  </body>
</html>
```

### `GET /sitemap.xml`

`SitemapController.index`: sets content type `application/xml` (Phoenix appends `; charset=utf-8`), status 200, body `Cache.fetch(:sitemap, &build/0, 30 minutes)`. The route is inside the `:browser` pipeline, which has `accepts ["html"]`; a request whose `Accept` header excludes both `text/html` and `*/*` is therefore refused with 406 before the controller runs. Crawlers send `*/*`, so this does not bite in practice.

URL list (deduplicated with `Enum.uniq`, in this order):

1. `/`, `/cases`, `/drafts`, `/linked`, `/reading`, `/works/new`
2. for each `Cases.published()` case `c`: `/cases/<c.slug>` then `/cases/<c.slug>/read`
3. for each `Works.public_drafts()` work `w`: `/drafts/<w.slug>`, plus `/drafts/<w.slug>/changes` only if `Works.revision_count(w.id) > 0`
4. for each `Links.public_links()` row: `/linked/<row.link.id>`
5. for each `Marginalia.Folders.published()` folder: `/reading/<folder.slug>`

Each is `Endpoint.url() <> path`, XML-escaped (`&`, `<`, `>` only). Body, exactly:

```
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemap.org/schemas/sitemap/0.9">
  <url><loc>https://host/…</loc></url>
  …one per line, joined with "\n"…
</urlset>
```

The namespace is spelled `sitemap.org`, not the standard `sitemaps.org`. That is what the code emits. A strict validator would reject it; a rewrite that must "look the same" should keep it, and one that wants to be correct should fix it and say so. There is no `lastmod`, `changefreq` or `priority`. Individual reading steps (`/reading/:slug/:ordinal`) and `/cases/:slug/read/:lead` are not listed.

## 6. Shared page components

### 6.1 `MarginaliaWeb.Walk.overlay/1` (the guided tour)

Attrs: `steps` (list, required), `auto` (string, default nil), `note` (string, default `Nothing here is saved, and no model is called — the answers are fixed examples.`).

Markup (the colocated `<script>` is stripped from the output and shipped in the JS bundle):

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

(The `<div id="walk">` is closed after the card.)

`data-steps` is `Jason.encode!(@steps)`. Each step is a map with keys (atoms become JSON keys) `id`, `title`, `body`, `target` (CSS selector or null), `place` (`"top" | "bottom" | "left" | "right" | "centre"`), and optionally `act`:

* `{kind: "push", event: "<name>", params: {...}}`: `pushEvent(event, params)` to the LiveView.
* `{kind: "click", target: "<selector>"}`: `document.querySelector(target)?.click()`.
* `{kind: "hop", to: "<name>"}`: `pushEvent("walk_hop", {to})`.
* any other `kind` (or none matching): `client(step.act.name)`, a named in-page action implemented in the hook (`open_map`, `open_thread`, `ask_thread`, `select`, `rewrite`, `edit`, `reset`); none of the case steps use these.

**Two modes.** With `auto` set (the cases index), the overlay is always rendered; the hook decides whether to run, using `localStorage["mg.tour.<auto>"] === "1"` as the seen flag, and the "Take the tour" button forces a run. Without `auto` (the case reading page), the overlay is rendered only while the server's `walk` assign is non-empty, and the hook starts at step 0 on mount; ending it pushes `end_walk`.

The hook, in full:

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

Events the hook can push to the host LiveView: `end_walk` (no params), `walk_hop` (`{to}`), and whatever a `push` step names. Hosts: `CaseLive.Index` handles `walk_hop` only; `CaseLive.Read` handles `end_walk`, `walk_hop`, `start_walk`.

DOM classes the CSS must style: `mg-walk-ring`, `mg-walk-veil`, `mg-walk-card` (+ `centre` modifier), `mg-walk-head`, `mg-label`, `n`, `mg-btn sm ghost ml-auto end`, `mg-walk-foot`, `back`, `next`, `mg-walk-safe`. The ring/veil/card start `hidden`; the hook toggles the `hidden` property and sets `top/left/width/height` inline on the ring and `top/left` on the card. The card width the placement maths assumes is `22rem` (22 * 16 px).

### 6.2 `MarginaliaWeb.LinkChat.bubble/1` (the chat bubble and panel)

Attrs and defaults: `open` (false), `history` (list of `%{"role" => "user" | "assistant", "content" => text}`, `[]`), `thinking` (false), `mutter` (list of strings, `[]`: the lines for the wait indicator, see 6.4), `count` (integer, 0), `cited` (list of edge structs, `[]`), `title` (`About this pair`), `label` (`Talk about how these two relate`), `hint` (`This one holds both maps and every edge between them. Ask what the second draft already answers, where the disagreement is real, or which connection is doing the most work. It will not write for either of them.`), `placeholder` (`How do these two sit together?`), `openers` (`["What does the second document already answer?", "Which disagreement here is real, and which is vocabulary?", "Which connection is doing the most work?"]`).

Markup:

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

      <.mutter :if={@thinking} lines={@mutter} label="reading" />
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

(Followed by the three hook scripts, stripped, and the closing `</div>` of `#linkchat`.)

Events pushed to the host: `toggle_chat` (the bubble and the `×`), `chat_send` (the form submit, with `message`; each opener button sends `chat_send` with `phx-value-message`), `uncite` (`edge` = edge id as string), and, from the hook, `close_chat`. While `thinking` is true the bubble renders `<.mutter :if={@thinking} lines={@mutter} label="reading" />` (section 6.4) where it previously rendered the bare three-dot `div.mg-dots`. The assistant's reply is rendered with `Marginalia.Markdown.to_html(content)` (hard breaks); the user's text is escaped plain text.

**`close_chat` is not handled by `CaseLive.Read`** (see section 8). The hook pushes it on any `Escape` keydown on the document (even with the panel closed) and on any `mousedown` outside the bubble while the panel is open.

The three hooks, in full:

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

(The first is `.LinkChat` on `#linkchat`, the second `.Composer` on `#lc-form`, the third `.StickDown` on `#lc-body`.)

### 6.3 `MarginaliaWeb.LinkWaiting.waiting/1`

Not rendered by any page in this scope (it belongs to the pairwise link reading, `LinkLive.Read`); documented because it lives in `components/`. Attrs: `a`, `b` (maps with `title`, required), `a_nodes`, `b_nodes` (lists of nodes with `title`, default `[]`), `status` (`"linking"`), `error` (nil). Computes `pairs = length(a_nodes) * length(b_nodes)`, `a_dots = sample(a_nodes)`, `b_dots = sample(b_nodes)`, where `sample` takes the titles, and if there are more than 24 picks `Enum.at(titles, trunc(i * n/24))` for `i in 0..23`. `y(i, n) = 30 + i * (300 / max(n - 1, 1))`.

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

(Followed by the hook script, which is stripped, and the closing `</div>` of `.lw`.)

The `.Wiring` hook:

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

Event pushed: `relink` (no params) from the failure state's `Try again` button, handled by `LinkLive.Read`.

### 6.4 `CoreComponents.mutter/1` (the wait indicator) and `Marginalia.Mutterings`

Added after the first draft of this spec. Replaces the bare three pulsing dots wherever a model is working (the case chat here; the private work page and pairwise link chat elsewhere). Imported everywhere through `CoreComponents`, so `<.mutter>` is callable in any LiveView or component.

Attrs: `lines` (list of strings, default `[]`), `label` (string, default `"thinking"`, used as `aria-label`), `class` (any, default nil, extra classes on the container). The element id is `"mutter-" <> Integer.to_string(:erlang.phash2(lines))`, so the same lines give the same id.

```heex
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
```

With `lines == []` only the three dots render (the state on a fresh install before the table is seeded). The first line is rendered server-side; `phx-update="ignore"` stops patches resetting the text mid-rotation. CSS (in `app.css`): `.mg-dots` is a flex row with `gap:.3rem`, `padding:.7rem 0`; `.mg-mutter` fades in over .32s (`mg-mutter-in`), `.mg-mutter.out` has opacity 0.

The `.Rotate` hook, in full:

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

**Data: `Marginalia.Mutterings`** (table `mutterings`: `text` unique, `source` default `"cron"`, timestamps). A page asks for lines when a model call starts: `Marginalia.Mutterings.some(8)`:

* picks up to 8 random rows (`ORDER BY random() LIMIT 8`, selecting `text`) whose text is not in the calling process's `:mutterings_seen` list (process dictionary; per LiveView process);
* if that gives none while `seen` is non-empty, clears `seen` and picks again;
* then stores `Enum.take(lines ++ seen, 40)` as the new seen list; returns the lines (`[]` when the table is empty).

`Mutterings.one/0` (one random text or nil) also exists. The table is filled by a supervised GenServer, `Mutterings.Clock` (started in the application supervisor): it ticks every 30 minutes; the first tick seeds up to 100 rows (`seed/1`: while `100 - count > 0`, call `generate(missing)`, at most 4 tries, stop at the first failed call once something was added), later ticks add 10 (`topup/1`, source `"cron"`). `generate(n)` makes one chat call: model `deepseek-chat` when the provider is DeepSeek, else `LLM.fast_model()`; `effort: :none`, `temperature: 1.2`, `max_tokens: 40 * n + 100`, `timeout: 60000`; messages: system = the character prompt below, user = `Give <n> of them. One per line. No numbering, no quotation marks, no introduction and no commentary: nothing but the words themselves.`. The reply is parsed line by line: trim; strip a leading bullet or number (`^(?:[-*•]|\d+[.)])\s*`); strip surrounding quote characters (`^["“„'‘]+|["”'’]+$`); drop empty lines, lines ending in `:`, lines longer than 240 characters; dedupe; take `n`; insert with `on_conflict: :nothing` on `text`. `{:error, :nothing_usable}` if no row survives. Prompt, verbatim (typo included):

```
You are Fyordor Dostoyevsky. You live in the modern day. You work a job at a grilled cheese sandwich factory in Menlo Park, CA. Give some words you might utter while working alone at teh sandwich counter. Keep it 240 characters or less.
```

A rewrite that has no table can pass a fixed list or `[]`; the component's contract is only "a list of strings".

## 7. Landing page: `GET /`

### 7.1 Route, auth, layout

`LandingLive` `:index`, `live_session :landing` with `on_mount: [{UserAuth, :mount_current_scope}]` (plus Freshness). Pipeline `:bare_browser`, root layout `bare`. No guest is created. The page does not call `Layouts.app`, so it has no app header, no `flash_group` (a flash set by a redirect to `/` is never displayed), and no `<main>` wrapper.

### 7.2 Mount

```elixir
def mount(_params, _session, socket) do
  {:ok, assign(socket, page_title: nil, notes_only: false)}
end
```

No context calls. `page_title` nil gives the default title (`Someone who has actually read the whole thing · Marginalia`), the default description (the pitch), the default card image `/images/og.png`, canonical `<host>/`. No `page_robots`.

### 7.3 Events

| event | params | effect |
|---|---|---|
| `toggle_notes` | none | `notes_only = !notes_only` |

That is the only server interaction. There is no `handle_params`, `handle_info`, timer, PubSub or async work.

### 7.4 Structure

The page is one `div#landing` (`phx-hook=".Reveal"`, class `mg`, plus ` notes-only` when `@notes_only`) holding a sticky header and eighteen `<section class="sec head" id="…">` blocks. Each section is a three-column grid (prose column, a 3rem dotted leader, a 30ch margin column):

```
<section class="sec head" id="ID">
  <div class="sec-title"><h1|h2>…</h1|h2></div>
  <div class="sec-leader"></div>
  <div class="sec-main"> …prose, demos, links… </div>
  <aside class="sec-aside"> <div class="note" data-reveal style="--i:N"><span class="who">KIND</span>…</div> … </aside>
</section>
```

The first section uses `<h1>` (class from `.mg h1`), all others `<h2>`. A `note` is `<div class="note" data-reveal style="--i:N">` (add class `act` for calls to action) containing `<span class="who">` with one of `note`, `tension`, `connection`, `observation`, `your turn`, `last note`, followed by the text.

All user-visible text is static. **The complete markup, verbatim, is in `blimp/notes/web-public-extracts/landing-body.heex`; the complete inline stylesheet is in `landing.css`.** The page emits the stylesheet as a `<style>` element at the top of the LiveView's render (before `div#landing`); it declares `:root` custom properties `--mg-paper:#fbfaf7; --mg-ink:#1c1a17; --mg-dim:#6b665e; --mg-rule:#e0dbd2; --mg-accent:#8a3324; --mg-margin:#f4f1ea; --mg-serif:…; --mg-sans:…` (these override or duplicate the ones in `app.css`). It must be reproduced as is.

`phx-no-curly-interpolation` is set on five `<code>` elements (`@today`, `owner/repo`, `state:closed -Bump`, `stat:closed`, `##`) so that HEEx treats their braces/characters literally; in a rewrite they are plain text.

Header:

```heex

<div id="landing" phx-hook=".Reveal" class={"mg" <> if(@notes_only, do: " notes-only", else: "")}>
  <div class="mg-head">
    <span class="mg-brand">Marginalia</span>
    <span class="right">
      <.link navigate={~p"/cases"}>Cases</.link>
      <button class={"mg-toggle" <> if(@notes_only, do: " on", else: "")} phx-click="toggle_notes">
        just the notes
      </button>
      <%= if @current_scope do %>
        <.link navigate={~p"/works"}>Your drafts</.link>
      <% else %>
        <.link navigate={~p"/users/log-in"}>Log in</.link>
      <% end %>
    </span>
```

Where `@current_scope` is the scope (nil for anonymous visitors). Consequence: anonymous visitors see `Log in` in the header and a second ghost CTA; guests and real users see `Your drafts` (`/works`) and no `Log in` CTA. The private helper `start_path/1` ignores its argument and returns `/works/new`, so every "Upload a draft" button, for everybody, goes to `/works/new`, which is under the guest-minting scope. Visiting `/works/new` creates the guest.

The first section:

```heex

  <section class="sec head" id="top">
    <div class="sec-title">
      <h1>Someone who has actually read the whole thing.</h1>
    </div>
    <div class="sec-leader"></div>
    <div class="sec-main">
      <p class="lede">
        Upload a draft. Marginalia reads it end to end, maps what's on the page, and then
        argues with you about it in the margin — one thread per paragraph, pinned where it
        belongs. No account, no setup.
      </p>
      <div class="ctas">
        <.link navigate={start_path(@current_scope)} class="cta">Upload a draft</.link>
        <%= if !@current_scope do %>
          <.link navigate={~p"/users/log-in"} class="cta ghost">Log in</.link>
        <% end %>
      </div>
      <p class="fine">Free while it's new. Your draft is private to whoever has its link.</p>
    </div>
    <aside class="sec-aside">
      <div class="note" data-reveal style="--i:0">
        <span class="who">note</span>
        <b>marginalia</b>, <i>n.</i> — what a reader leaves in the margin. The book goes back
        on the shelf exactly as it was printed. Everything down this side of the page is the
        product, annotating its own pitch as you scroll.
      </div>
    </aside>
```

`seeit/1` (private function component, attrs `to`, `label`): `<p class="seeit"><.link navigate={@to}>{@label} →</.link></p>`.

### 7.5 Section index

| `id` | heading | extras in `.sec-main` | links out | margin notes (who) |
|---|---|---|---|---|
| `top` | `Someone who has actually read the whole thing.` (h1) | `p.lede`, `.ctas`, `p.fine` | `/works/new` (`cta` "Upload a draft"); anonymous only: `/users/log-in` (`cta ghost` "Log in") | 1 (note) |
| `why` | Nobody finishes your draft | 1 paragraph | | 1 (note) |
| `the-read` | It reads all of it, and you watch | 2 paragraphs | seeit `/drafts/TGokc15wZbB6WGUJuE0Dcg`, "A dissent it read end to end, 165 notes" | 2 (note, note) |
| `anchoring` | Pinned to your own sentences | `.demo > p.src` with `span.mark` | seeit `/drafts/TGokc15wZbB6WGUJuE0Dcg`, "Every note here is anchored to a sentence" | 2 |
| `margin` | The page, with its notes in the margin | `.mg-chips` (`<b>Everything</b>` + three `<span>`s), 3 paragraphs | seeit `/drafts/TGokc15wZbB6WGUJuE0Dcg`, "See the page it produces" | 2 |
| `threads` | A thread on one paragraph | `.mg-gut[data-reveal]` (a `span.tick`, a paragraph, `.turns` with `.you` and `.it`); `.play[data-reveal]` with `.cap`, `.turns`, three `.turn` (`you`, `think`, `it`) each with `style="--i:N"` | none | 3 (note, note, note) |
| `graph` | What leads to what | `.mg-edges[data-reveal]` with `.cap` and three `.e` rows (`span.n`, `span.rel`, `span.n` [`hollow` on the second row's far end], `span.why`) | `note-cta` "Find yours →" to `/works/new` | 2 (note, `note act` "your turn") |
| `rewrites` | The one place it writes | `.mg-cands[data-reveal]` (`.cap`, `.c.orig`, three `.c.alt` with `style="--i:0..2"`, `ins`/`del` inline); two paragraphs; `.wont` with a `ul` of four `li`; `.play[data-reveal]` | `note-cta` "Try to break it →" `/works/new` | 3 (tension, note, `note act` your turn) |
| `editing` | Then you change it yourself | 2 paragraphs | | 1 |
| `retrieval` | It goes and looks | `.fx[data-demo][data-interval="620"]` with `.cap`, three `.d-call[data-step=1..3]` (`span.tool`, `span.arg`, `span.hit`), `p.d-reply[data-step=4]`; 3 paragraphs | seeit `/drafts/Eba9cP98i1LVY5fA8QZtdA`, "A draft it has read, to ask about"; `note-cta` "Try to break it →" | 3 (note, tension, `note act` your turn) |
| `summaries` | Where you are in twelve sections | `.fx[data-demo][data-interval="700"]` with `.d-head` (`span.d-lab`, `span.d-title`, `span.d-btn[data-step=1]`), `p.d-sum[data-step=2]`, `.d-chips[data-step=3]`, `.d-links[data-step=4]`; 3 paragraphs | seeit `/drafts/Eba9cP98i1LVY5fA8QZtdA`, "Twelve sections, each summarised" | 2 (note, connection) |
| `changes` | Every change, kept | `.fx[data-demo][data-interval="800"]` with `.d-cols` (`.d-colhead`, `.d-row` with `.d-side.d-old` containing `del[data-step=1]` and `.d-side.d-new` containing `ins[data-step=2]` x2), `.d-log[data-step=3]`, `.d-log[data-step=4]` (each with `span.sha`); 2 paragraphs (one with `<code>git log -p</code>`) | seeit `/drafts/DhEGqQm_go9N3wm9Y4tCWg/changes`, "Three changes to a real draft, before and after" | 2 (note, `note act` tension) |
| `links` | Two drafts, and what runs between them | `.fx.link[data-demo][data-interval="700"]` with `.d-link` grid: two `.d-col` (each `span.d-col-name` + three `span.d-node[data-step=1|3|5]`), `.d-edges` (three `span.d-edge[data-step=2|4|6]`, the third also `tension`, each with `<i>`), `p.d-edge-note[data-step=7]`; 3 paragraphs | seeit `/linked`, "Pairs read against each other, and what they found" | 2 (note, connection) |
| `import` | Forty pull requests in, one edited draft out | 2 paragraphs; `.fx.pipe[data-demo][data-interval="430"]` with eight `.d-stage[data-step=1..8]` (`span.d-what > b`, `span.d-detail`); paragraph; `.ctas` | `cta` "Bring in a repository →" `/import` | 2 (note, `note act` tension) |
| `stacks` | A hundred and eleven pull requests, read forwards | 2 paragraphs; `.fx.stack[data-demo][data-interval="520"]` with `.d-ticks[aria-hidden]` (a repeating-gradient bar, one element), three `.d-move[data-step=1..3]` (`strong` + `span.mg-meta`), `.d-revised[data-step=4]`; `.ctas` | `cta` "Read the one it produced →" `/reading/a-temper-backend-for-blimp-pull-request-stack` | 2 (note, observation) |
| `reading` | Or read one it has already done | paragraph, `.ctas`, `p.fine` | `cta` "The cases →" `/cases` | 1 |
| `costs` | What it costs, and where your draft goes | 2 paragraphs, `p.fine` | | 2 (note, tension) |
| `start` | Bring the draft in the drawer. | `.ctas` + `p.fine` | `cta` "Upload a draft" `/works/new`; `note-cta` "Upload a draft →" | 1 (`note act`, who = "last note") |

The ids are part of the interface (people link to `/#changes`, `/#summaries`, `/#links`); `.sec` has `scroll-margin-top:5rem` to clear the sticky header. Hard-coded production data: three draft slugs (`TGokc15wZbB6WGUJuE0Dcg`, `Eba9cP98i1LVY5fA8QZtdA`, `DhEGqQm_go9N3wm9Y4tCWg`) and one folder slug. If those documents do not exist in the new deployment the links 404 (the page does not check).

### 7.6 Hook `.Reveal` (on `div#landing`)

Purpose: one-shot scroll-triggered reveal. Nothing is hidden until the hook runs: it adds class `reveal-ready` to `#landing` (CSS then hides `.note`, `.turn`, `.fx [data-step]`, `.mg-cands .c.alt` with opacity 0). It skips everything (leaving the page fully visible) if the user prefers reduced motion or there is no `IntersectionObserver`. An observer (`rootMargin: "0px 0px -12% 0px"`, `threshold: 0.15`) adds class `in` to each `[data-reveal], [data-demo]` element the first time it intersects, then unobserves it. For `[data-demo]` elements it also schedules `play`: the `[data-step]` descendants sorted by numeric `data-step`, each getting class `on` after `interval * (index + 1)` ms (`data-interval`, default 650). The hook is never re-run on server patches (no `updated`), so toggling `notes-only` does not replay animations.

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

### 7.7 "Just the notes"

The `mg-toggle` button (`phx-click="toggle_notes"`, class `mg-toggle` + ` on` when active, label always `just the notes`) toggles the class `notes-only` on `#landing`. CSS (inside `landing.css`) hides `.sec-main` and `.sec-leader` and lays the notes out single column at `.92rem`.

## 8. Cases

The cases are the Supreme Court documents the owner has filed under a named collection. A "case" is not a table: it is the set of the owner's works that share a `collection` string, with `collection_role` giving reading order.

### 8.0 The data model the three case pages share

`Cases.published/0` (cached, key `:published_cases`, 5 min) returns `[]` when there is no owner, else `Cases.list(owner.id)`:

1. all of the owner's works with a non-null `collection`, ordered by `collection` asc, `id` asc;
2. `kinships` across collections (see `kin` below);
3. every `Link` touching any of those works (`a_work_id in ids or b_work_id in ids`, with `a_work`, `b_work` preloaded) and every `LinkEdge` of those links (ordered `ordinal asc, id asc`, with `from` and `to` nodes preloaded), grouped by link id;
4. grouped by `collection`, one map per collection, sorted by `name`.

Each case map has:

| key | meaning |
|---|---|
| `name` | the collection string, e.g. `Trump v. Slaughter` |
| `slug` | `Cases.slug(name)` |
| `works` | the case's works sorted by role rank (`opinion` 0, `concurrence` 1, `dissent` 2, `argument` 3, anything else 4; stable, so ties stay in id order) |
| `links` | only links with **both** ends inside this case (a link to another case is excluded) |
| `by_link` | `%{link_id => [LinkEdge]}` for those links; `rationale` here is the raw model text with its "A"/"B" references unresolved |
| `holding` | the opinion's holding sentence, see below, or nil |
| `read` | count of works with `status == "read"` |
| `words` | sum of `word_count` |
| `edges` | total edges across `by_link` |
| `missing` | pairs of works with no link (unused by these pages) |
| `kin` | list of `%{link_id, lead, other, case, edges}`, other cases this case is linked to; sorted by edges desc |

**Holding** (`Cases.holding/1`, applied to the work whose role is `opinion`): flatten whitespace (`\s+` to one space) in the body, then try these regexes in order, taking the first that matches: `\b[Ww]e (?:therefore |accordingly |now )?hold that\b[^.]{20,300}\.`, `\b[Ww]e (?:therefore |accordingly |now )?conclude that\b[^.]{20,300}\.`, `\b[Ww]e (?:hold|conclude)\b[^.]{20,300}\.`, `\bWe (?:therefore |accordingly )?(?:reverse|affirm|vacate)\b[^.]{10,300}\.`. The matched text is widened back to the start of its sentence (the last `[.!?][”"]?\s+` before the match marks the boundary; start of text if none), then leading division markers are repeatedly stripped (`^\s*(?:[IVXL]{1,5}|[A-Z]|\d{1,2}|\*(?:\s*\*)*)[\s.]+`, applied until it no longer changes the text or would empty it), then trimmed. nil if nothing matches (the page says three of sixteen have none).

**Work fields used:** `id`, `slug`, `title` (convention `"<Case name> — <Document name>"`), `collection`, `collection_role`, `word_count`, `source_url`, `first_impression`, `status`, `body`.

**`Cases.preview(c)`:** `edges` = all edges from `by_link` values, flattened, stably sorted by `tension` 0, `answers` 1, `requires` 2, everything else 3. Returns `%{summary, sharpest: first 3 edges, kinds, impression}`; `impression` is the opinion work's `first_impression` (nil if no opinion). The pages use `impression` and `sharpest`.

**`Cases.ways(c)`:** for each link with `status == "linked"` whose two works are both in the case: `lead` is the work with the lower role rank (`a` on ties), `other` the other, `edges` the length of `by_link[link.id]`; drop those with 0 edges; sort by `{rank(lead.role), -edges}` (stable). Each is `%{link, lead, other, edges}`.

**`Cases.default_lead(c)`:** the work with role `opinion`, else the first work, else nil. **`Cases.roles/0`:** `["opinion", "concurrence", "dissent", "argument"]`.

**`Record.for(name)`** returns `%{docket, argued, decided}` (strings: `"No. 25-332"`, `"December 8, 2025"`, `"June 29, 2026"`) and sometimes `question` for the 16 hard-coded case names in `Cases.Record` (Blanche v. Lau, Chatrie v. United States, Cisco Systems v. Doe, Exxon Mobil Corp. v. Corporacion Cimex, Landor v. Louisiana, Monsanto Co. v. Durnell, Mullin v. Al Otro Lado, Mullin v. Doe, National Republican Senatorial Committee v. FEC, Pung v. Isabella County, T. M. v. University of Maryland Medical System, Trump v. Barbara, Trump v. Slaughter, Watson v. Republican National Committee, West Virginia v. B. P. J., Wolford v. Lopez), or nil for any other name. `question` exists only for Chatrie, Landor, Trump v. Slaughter and West Virginia v. B. P. J. The full table is `lib/marginalia/cases/record.ex`; a rewrite needs it as data.

**Role/title helpers used by several templates**, all the same function under different names (`short`, `role`, `short_title`): split `title` on the first `" — "` (space, em dash, space); if there are two parts the second, else the whole title.

### 8.1 `/cases`: `CaseLive.Index`

**Route/auth/layout:** public, `:cases` live_session, root layout `root`, `Layouts.app` without `bleed`.

**Mount:**

```elixir
cases = Cases.published()
        |> Enum.map(fn c -> c |> Map.put(:preview, Cases.preview(c)) |> Map.put(:record, Record.for(c.name)) end)
assign(socket,
  page_title: "The term, read closely",
  page_description: description(cases),
  page_image: ~p"/images/og-cases.png",
  page_image_alt: "A line of a Supreme Court opinion, highlighted, with a line drawn across to the dissent arguing with that exact sentence in the margin.",
  page_url: url(~p"/cases"),            # absolute: <host>/cases
  cases: cases, open: nil,
  words: sum of case.words, docs: sum of length(case.works), edges: sum of case.edges,
  span: span(cases), opener: opener(cases))
```

`description/1`: no cases gives `Supreme Court cases, read document by document and related to each other.`; otherwise `"<N> Supreme Court cases, <D> documents — every opinion, concurrence, dissent and advocate's argument read on its own, then read against each other, with every connection anchored to a sentence in both."` (N is not pluralised: `1 Supreme Court cases`). No `page_robots`.

`span/1`: collect `record.decided` strings, extract the trailing 4-digit year with `(\d{4})\s*$`, unique and sorted. None gives `""`; one year `y` gives `"'s <y-1> term"`; several gives `"'s <min-1>–<max-1> terms"` (en dash). (So a decision year of 2026 prints "2025 term".)

`opener/1`: for each case, `tensions` = every edge in `by_link` of its `links` with `edge_type == "tension"`; keep cases with at least one; choose the case with the most tensions (first wins ties in `name` order); within it `pick` = the tension whose `String.length(rationale || "")` is closest to 170 (first on ties). Result `%{case, count, edge}` or nil. The rationale used is raw (unsubstituted A/B).

**Render:** (tour overlay, then page body; `fmt/1` is `n >= 1000 -> "#{Float.round(n / 1000, 1)}k"` else `to_string(n)` so 2000 prints `2.0k`, and `plural(1, w) = w`, else `w <> "s"`)

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <%!-- Always rendered; the hook decides whether to run it, against
        a flag in this browser. That is what lets this page work with
        no account at all. --%>
  <MarginaliaWeb.Walk.overlay
    steps={Walkthrough.Cases.steps(:cases)}
    auto="cases"
    note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
  />

  <div class="cs">
    <header class="cs-top">
      <h1>The term, read closely</h1>
      <p class="lede">
        {length(@cases)} {plural(length(@cases), "case")} from the Supreme Court{@span}. Each arrives as a pile of
        separate documents — the opinion of the Court, everything written alongside or
        against it, and every advocate's turn at the lectern — and each one is read on
        its own terms before any of them are compared.
      </p>
      <p class="how1">
        Each document read on its own, then related to the others — so you can read the
        opinion with the dissent following along beside it, snapping to whatever it is
        answering.
      </p>
      <button class="cs-tour" phx-click={Phoenix.LiveView.JS.dispatch("mg:walk", to: "#walk")}>
        Take the tour <span aria-hidden="true">→</span>
      </button>

      <p class="tally">
        <span><b>{length(@cases)}</b> {plural(length(@cases), "case")}</span>
        <span><b>{@docs}</b> {plural(@docs, "document")}</span>
        <span><b>{fmt(@words)}</b> words</span>
        <span><b>{@edges}</b> connections drawn between them</span>
      </p>
    </header>

    <%!-- One real connection, before any explanation of what a
          connection is. The page is making an unusual claim and the
          fastest way to make it concrete is to show the thing. --%>
    <section :if={@opener} class="cs-opener">
      <span class="mg-label">for instance</span>
      <p class="q">{@opener.edge.rationale}</p>
      <p class="src">
        one of <b>{@opener.count}</b> places the documents in
        <em>{@opener.case.name}</em>
        pull against each other —
        <.link navigate={~p"/cases/#{@opener.case.slug}/read"}>read it →</.link>
      </p>
    </section>

    <p :if={@cases == []} class="none">Nothing here yet.</p>

    <article :for={c <- @cases} class="cs-case">
      <div class="cs-case-head">
        <h2><.link navigate={~p"/cases/#{c.slug}/read"}>{c.name}</.link></h2>
        <span :if={c.record} class="rec">
          <span class="dk">{c.record.docket}</span>
          <span>Argued {c.record.argued}</span>
          <span>Decided {c.record.decided}</span>
        </span>
      </div>

      <%!-- What the Court was asked, where that is written; otherwise
            the Reporter's own statement of what it decided. Both are
            the line a reader checks before opening anything. --%>
      <p :if={c.record && c.record[:question]} class="qp">
        <span class="mg-label">question presented</span>
        {c.record.question}
      </p>
      <%!-- The Court's own sentence, quoted. It was the Reporter's
            headnote, which is the obvious source and the wrong one:
            the syllabus is not part of the opinion, carries no
            authority, and a lawyer does not read it. --%>
      <blockquote :if={c.holding} class="cs-held">
        <span class="mg-label">the Court, holding</span>
        {c.holding}
      </blockquote>

      <%!-- The read pass's own account of the opinion, written before any
            of the comparing. It is the most useful paragraph on the page
            and it was being computed and thrown away. --%>
      <div :if={c.preview.impression} class="cs-fi">
        <span class="mg-label">on reading the opinion</span>
        <p class={["fi", @open != c.slug && "clamped"]}>{c.preview.impression}</p>
        <button phx-click="impression" phx-value-slug={c.slug} class="more">
          {if @open == c.slug, do: "less", else: "more"}
        </button>
      </div>

      <%!-- The hook: the sharpest thing the pass found between these
            documents, in its own words. A reader decides whether to
            open a case on a sentence, not on a count. --%>
      <p :if={hook(c)} class="cs-hook">{hook(c).rationale}</p>

      <%!-- And then the actual ways in. A case is not read as a case,
            it is read as one document against another, scrolling —
            so the card offers the pairings themselves, best first,
            each landing in the reading where the second follows the
            first. --%>
      <ul class="cs-ways">
        <li :for={w <- Enum.take(Cases.ways(c), 3)}>
          <.link navigate={~p"/links/#{w.link.id}?lead=#{w.lead.slug}"}>
            <span class={["a", w.lead.collection_role]}>{short(w.lead.title)}</span>
            <span class="x" aria-hidden="true">against</span>
            <span class={["b", w.other.collection_role]}>{short(w.other.title)}</span>
            <span class="n">{w.edges}</span>
            <span class="arrow" aria-hidden="true">→</span>
          </.link>
        </li>
      </ul>

      <details :if={c.preview.impression} class="cs-fi">
        <summary>
          <span class="mg-label">on reading the opinion</span>
          <span class="peek">{c.preview.impression}</span>
        </summary>
        <p>{c.preview.impression}</p>
      </details>

      <%!-- The term arguing with itself: the only thing on this page
            that could not have come from reading one case carefully. --%>
      <div :if={(kin = Cases.kin(c)) != []} class="cs-kin">
        <span class="mg-label">elsewhere in the term</span>
        <.link
          :for={k <- Enum.take(kin, 3)}
          navigate={~p"/links/#{k.link_id}?lead=#{k.lead.slug}"}
          class="k"
        >
          {k.case} <span class="n">{k.edges}</span>
        </.link>
      </div>

      <%!-- The inventory, and where each piece came from. Quiet, but
            not optional: the page's whole claim is that none of this
            is invented, and the only way to make that checkable is to
            keep the source one click away. --%>
      <div class="cs-parts">
        <ul>
          <li :for={w <- c.works} class={w.collection_role}>
            <.link navigate={~p"/cases/#{c.slug}/read/#{w.slug}"} class="t">{label(w)}</.link>
            <span class="n">{fmt(w.word_count)}</span>
            <a
              :if={w.source_url}
              href={w.source_url}
              rel="noopener"
              class="pdf"
              title="The PDF this was made from"
            >pdf</a>
          </li>
        </ul>
      </div>

      <div class="cs-case-foot">
        <.link navigate={~p"/cases/#{c.slug}/read"} class="go">
          or all {length(c.works)} at once →
        </.link>
        <.link navigate={~p"/cases/#{c.slug}"} class="go">
          all {c.edges} connections →
        </.link>
      </div>
    </article>

    <%!-- The method used to sit above the list, on the theory that
          nothing makes sense without it. It does not earn that place:
          five paragraphs between a reader and the first real
          disagreement is five paragraphs they leave on. Folded, and
          after the cases, where someone who has seen the thing work
          will go looking for how. --%>
    <details class="cs-how">
      <summary><span class="mg-label">how this works</span></summary>
      <ol>
        <li>
          <b>The Reporter's syllabus is not one of the documents.</b>
          Every slip opinion opens with a headnote summarising itself, and every slip
          opinion says on the same page that the headnote "constitutes no part of the
          opinion of the Court". It is not read here and nothing on this site is drawn
          from it. Where a case states its holding below, that is the Court's own
          sentence, quoted out of the opinion; three of these sixteen never put their
          holding in one sentence, and those cases show none.
        </li>
        <li>
          <b>Every document is read separately.</b>
          Not summarised — read. Each paragraph gets the beats it contains, anchored to
          a sentence copied out of the document character for character, and above those
          sit the spine of the argument, the threads that run through it, and the
          questions it leaves open.
        </li>
        <li>
          <b>An argument is split at the lectern.</b>
          A transcript is not one document. Each advocate's turn is its own case to make,
          with its own questions from the bench, so each is read as its own draft. The
          difference is not cosmetic: kept whole, one argument came back with 44
          connections to its opinion, and split it came back with 215.
        </li>
        <li>
          <b>Then the documents are related to each other.</b>
          Not the texts — the maps. A pass reads both graphs and draws the edges between
          them: what one develops, what it answers, and where the two genuinely pull
          apart. An edge that does not land on a real anchored passage in both documents
          is thrown away before it is stored.
        </li>
        <li>
          <b>Then you read the case with the case in the margin.</b>
          The opinion down the left, and every other document beside it at once — the
          dissent and both advocates on the same paragraph, each saying which one it is.
          Or take them two at a time, one following the other as you scroll, with a line
          drawn between the passages and the reason in the middle.
        </li>
        <li>
          <b>And you can argue with it.</b>
          Every passage can be talked about, on its own or against its counterpart in
          another document. Click the line between two passages and both go into the
          question.
        </li>
      </ol>
    </details>

    <%!-- What a reader is entitled to know about where this came from
          and what it is worth. Last, because it is the answer to a
          question you only have once you have seen the rest. --%>
    <footer :if={@cases != []} class="cs-prov">
      <span class="mg-label">about these</span>
      <p>
        The documents are slip opinions and argument transcripts published by the
        Supreme Court of the United States; every one links to the PDF it was made
        from. The Reporter's syllabus is excluded — it is no part of the opinion and
        says so itself — as are the headnotes of any other reporter. The reading and the connections are machine-made, and every passage
        quoted back to you is verified against the source before it is stored — a
        quote that cannot be found in the document, character for character, is
        discarded rather than shown. Nothing here is a summary, a headnote, or legal
        advice, and none of it is a substitute for reading the opinion.
      </p>
    </footer>
  </div>
</Layouts.app>
```

Notes on the render:

* `label(w)` is `"Opinion of the Court"` when `collection_role == "opinion"`, otherwise `short(w.title)`.
* `<details class="cs-fi">` repeats the impression in a collapsed form; it is **in addition to** the `div.cs-fi` clamp above it, so the impression appears twice per case (CSS decides which is visible per viewport).
* `.cs-ways` shows `Enum.take(Cases.ways(c), 3)`. The link target is `/links/<link.id>?lead=<lead.slug>`, the pairwise reading in another scope. The class on the two `span`s is `a <role>` and `b <role>` (role is `collection_role`, e.g. `a opinion`, `b dissent`).
* `kin` links also go to `/links/<link_id>?lead=<lead.slug>`.
* The "Take the tour" button dispatches the DOM event `mg:walk` at `#walk` (client-side, no server round trip).

**Events:**

| event | params | effect |
|---|---|---|
| `impression` | `slug` | `open = nil` if equal to the given slug, else the slug (one clamp open at a time; button label `more`/`less`; class `clamped` on `p.fi` when closed) |
| `walk_hop` | `to` = `"first_pair"` | `first_pair(cases)`: for the first case (alphabetical), the first of `Cases.ways(c)`, giving path `/links/<link.id>?lead=<lead.slug>&walk=1`, then `push_navigate` there. No cases, or no ways: `assign(walk: [])` and stay. Any other `to` value raises `FunctionClauseError` (the LiveView crashes and remounts). |

No `handle_params`, `handle_info`, async, timers or PubSub.

**Tour steps** (`Walkthrough.Cases.steps(:cases)`, serialised to `data-steps`; in order):

1. `hook`: "One real disagreement, first". Body: "Every case leads with the sharpest thing found between its documents, in the terms the pass used. Not a summary of the case — a place where two of its documents pull against each other." Target `.cs-case:first-of-type .cs-hook`, place `bottom`.
2. `held`: "The holding is the Court's own sentence". Body: "Quoted out of the opinion, not paraphrased, and not taken from the Reporter's syllabus — which is no part of the opinion and says so on its own first page. Three of these sixteen never state their holding in one sentence, and those show none at all." Target `.cs-case:first-of-type .cs-held`, `bottom`.
3. `ways`: "A case is read one document against another". Body: "Not 'open the case'. The opinion against the dissent, the opinion against the advocate it is answering — each with how much the two actually have to say to each other, which is the honest signal of which to open." Target `.cs-case:first-of-type .cs-ways`, `top`.
4. `kin`: "And the term argues with itself". Body: "Cases are related across the term too, chosen by the vocabulary the opinions actually share rather than by anyone's idea of a theme. It is the only thing here that could not have come from reading one case carefully." Target `.cs-case:first-of-type .cs-kin`, `top`.
5. `sources`: "Everything links back to the PDF". Body: "The whole claim of this site is that none of it is invented. The only way to make that checkable is to keep the Court's own file one click away, so every document does." Target `.cs-case:first-of-type .cs-parts`, `top`.
6. `into`: "Now the reading itself". Body: "This is where the site actually happens. Opening the strongest pairing in the first case." Target `.cs-case:first-of-type .cs-ways li:first-child`, `top`, `act: {kind: "hop", to: "first_pair"}`.

The overlay is rendered with `auto="cases"` (so the tour runs automatically on first visit, tracked in `localStorage["mg.tour.cases"]`) and `note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."`.

The tour's next leg is the pairwise reading `/links/:id?lead=…&walk=1` (`Walkthrough.Cases.steps(:follow)`, owned by `LinkLive.Read`), and the third leg arrives at `/cases/:slug/read?walk=1`. The `:follow` and `:case_read` step lists are given in 8.3.

### 8.2 `/cases/:slug`: `CaseLive.Show`

**Route/auth/layout:** public, `Layouts.app` without bleed.

**Mount** (`%{"slug" => slug}`): `Cases.published() |> Enum.find(&(&1.slug == slug))`. Missing: flash error `No such case.`, `push_navigate` to `/cases`. Found:

```elixir
assign(socket,
  page_title: c.name, page_url: url(~p"/cases/#{c.slug}"), page_image: ~p"/images/og-cases.png",
  case: c, all: edges(c), q: "", kind: nil, pair: nil, open: nil, shut: false) |> filter()
```

No description (default pitch), no `page_image_alt` (default alt, which describes the site card), no robots meta.

`edges(c)`: for each link in `c.links`, `Links.edges(link)` (a fresh query per link; the rationale has "Manuscript A/B" references resolved to document names by `Links.plain/2`), each mapped to

```
%{edge: LinkEdge(+from,to nodes), link: Link, from_work: work, to_work: work,
  pair: sorted([from_work.role, to_work.role]) |> join("+")   # "?" if either work is missing
  haystack: [rationale, from.title, to.title, from.quote, to.quote] (nil dropped) joined by " ", downcased}
```

then all sorted (stable) by edge type: `tension` 0, `answers` 1, `requires` 2, `develops` 3, `pays_off` 4, others 5.

`filter/1` recomputes `shown` from `all`: `kind` exact match on `edge.edge_type` (when set), `pair` exact match (when set), and `q` (trimmed, downcased) substring of `haystack` (when non-empty). Filters AND together.

`Links.plain/2` (resolution of "A"/"B"): a single left-to-right regex pass `(\A|\bManuscripts?\s+|[.;:—-]\s+|\s+)([AB])(['’]s)?(?![\p{L}\p{N}'’])` with a function replacement: `Manuscript A` becomes the document name (the part of the work title after `" — "`, else the whole title) with the possessive kept; `A's` is replaced anywhere; a bare `A`/`B` is replaced only at the start of the text or after `.`, `;`, `:`, `—`, `-` plus whitespace; a bare letter mid-sentence is left alone.

`Reading.plain(q)` (used on quotes): replace `[text](url)` with `text`; delete characters `` ` * _ ~ ``; strip leading `#`s per line (`^#+\s*` multiline); collapse whitespace to a single space; trim.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="cs-one">
    <div class="cs-one-top">
      <.link navigate={~p"/cases"} class="back">← all cases</.link>
      <h1>{@case.name}</h1>
      <span class="tally">
        {length(@case.works)} documents · {commas(@case.words)} words · {length(@all)} connections
      </span>
      <button class="fold" phx-click="toggle_docs">
        {if @shut, do: "show the documents", else: "hide the documents"}
      </button>
    </div>

    <div :if={not @shut} class="cs-docs">
      <section :for={w <- @case.works} class={["doc", w.collection_role]}>
        <div class="head">
          <span class="mg-label">{role(w)}</span>
          <span class="n">{w.word_count} words</span>
        </div>
        <p :if={w.first_impression} class="impression">
          {String.slice(w.first_impression, 0, 340)}…
        </p>
        <.link navigate={~p"/works/#{w.slug}"} class="open">Read it →</.link>
      </section>
    </div>

    <%!-- Straight into the thing this is all for: one document read
          down the left with another following along on the right. It
          was reachable only from inside a connection, three clicks and
          a scroll away from the top of the page. --%>
    <%!-- The whole case at once comes first. Reading the opinion
          against one other document at a time is the specialist move;
          what a reader wants on arrival is the opinion with everything
          else in the margin. --%>
    <div class="cs-all">
      <.link navigate={~p"/cases/#{@case.slug}/read"} class="cs-all-go">
        <span class="mg-label">read the case</span>
        <span class="t">{lead_title(@case)}</span>
        <span class="s">
          with {others_count(@case)} other documents in the margin — the dissent and the
          argument on the same paragraph
        </span>
      </.link>
    </div>

    <div class="cs-go">
      <span class="mg-label">or one against another</span>
      <div class="ways">
        <.link
          :for={l <- @case.links}
          navigate={~p"/links/#{l.id}?lead=#{lead_slug(@case, l)}"}
          class="way"
        >
          <span class="t">{way(@case, l)}</span>
          <span class="n">{count(l)} connections</span>
        </.link>
      </div>
    </div>

    <%!-- The connections, in a box you can slice rather than a column
          you scroll past. --%>
    <div class="cs-find">
      <div class="bar">
        <form phx-change="search" class="q" id="cs-q">
          <input
            type="search"
            name="q"
            value={@q}
            placeholder="Search the reasons and both passages — consent, Humphrey's, stare decisis…"
            phx-debounce="150"
            autocomplete="off"
          />
        </form>
        <span class="count">
          {length(@shown)}<span :if={length(@shown) != length(@all)}> of {length(@all)}</span>
        </span>
        <%!-- `or` demands a boolean on its left, and a nil filter is
              not one: `false or nil` raises rather than returning nil --%>
        <button :if={filtered?(@q, @kind, @pair)} class="clear" phx-click="clear">clear</button>
      </div>

      <div class="chips">
        <button
          :for={{k, n} <- counts(@all, & &1.edge.edge_type)}
          class={["chip", k, @kind == k && "on"]}
          phx-click="kind"
          phx-value-k={k}
        >{String.replace(k, "_", " ")} <span class="n">{n}</span></button>

        <span class="sep" aria-hidden="true"></span>

        <button
          :for={{p, n} <- counts(@all, & &1.pair)}
          class={["chip pair", @pair == p && "on"]}
          phx-click="pair"
          phx-value-p={p}
        >{pair_label(p)} <span class="n">{n}</span></button>
      </div>

      <div class="rows" id="edges">
        <p :if={@shown == []} class="nothing">
          Nothing matches that. <button phx-click="clear">Clear the filters</button>
        </p>

        <div
          :for={e <- @shown}
          class={["row", e.edge.edge_type, @open == e.edge.id && "open"]}
        >
          <button phx-click="open" phx-value-id={e.edge.id}>
            <span class="rel">{String.replace(e.edge.edge_type, "_", " ")}</span>
            <span class="why">{e.edge.rationale}</span>
            <span class="who">{short(e.from_work)}→{short(e.to_work)}</span>
          </button>

          <div :if={@open == e.edge.id} class="both">
            <div class="side">
              <span class="mg-label">{role(e.from_work)} · {e.edge.from.title}</span>
              <blockquote :if={e.edge.from.quote}>{plain(e.edge.from.quote)}</blockquote>
            </div>
            <div class="side">
              <span class="mg-label">{role(e.to_work)} · {e.edge.to.title}</span>
              <blockquote :if={e.edge.to.quote}>{plain(e.edge.to.quote)}</blockquote>
            </div>
            <.link navigate={~p"/links/#{e.link.id}"} class="read">
              Read these two side by side →
            </.link>
          </div>
        </div>
      </div>
    </div>
  </div>
</Layouts.app>
```

Details the markup does not make obvious:

* The heading counts use `commas(n)`: digits grouped by thousands with `,`. The per-document word count in `.doc .head .n` is **not** comma-formatted.
* `role(w)` is the document name (title after `" — "`); `role(nil)` is `"—"`. `short(w)` in `.who` is `Op`, `Diss`, `Conc`, `Arg` or `?` by `collection_role` (`—` for nil), printed `FROM→TO` with no spaces.
* `ends(c, link)` returns the link's two works sorted by `opinion 0, concurrence 1, dissent 2, argument 3, other 4`; `lead_slug` is the first one's slug; `way(c, l)` is `"<role(a)> ↔ <role(b)>"`; the `.ways` row count is `Links.edges(link) |> length` (queried again on every render) printed as `<n> connections` (always plural).
* **Every link in `case.links` is listed under "or one against another"**, including any whose status is not `linked` or that have no edges (unlike the index, which filters through `Cases.ways`).
* The chip list for kinds is `counts(@all, & &1.edge.edge_type)`: `Enum.frequencies_by`, then sorted by count descending (ties in key order); likewise `counts(@all, & &1.pair)`.
* `pair_label("dissent+opinion")` is `Dissent ↔ Opinion` (split on `+`, `String.capitalize`, join with ` ↔ `).
* `.hide the documents` / `show the documents` toggles `shut`; the `cs-docs` block is removed (not hidden) when `shut`.
* `first_impression` is truncated with `String.slice(text, 0, 340)` and `…` is always appended, even to shorter text.
* The "Read it →" link goes to `/works/<w.slug>` (the owner-or-link-holder reading page in the guest-minting scope).
* `filtered?(q, kind, pair)` is `q != "" or kind != nil or pair != nil`; the `clear` button appears when true. `q` is compared untrimmed there, so a single space counts as filtered although it matches everything.

**Events:**

| event | params | effect |
|---|---|---|
| `search` | `q` (form `phx-change`, input debounced 150 ms) | `q = q`, recompute `shown` |
| `kind` | `k` | toggle `kind` (set, or clear if same), recompute |
| `pair` | `p` | toggle `pair`, recompute |
| `clear` | none | `q = ""`, `kind = nil`, `pair = nil`, recompute (does not close `open`) |
| `open` | `id` (edge id string) | `String.to_integer`; toggle `open` |
| `toggle_docs` | none | `shut = !shut` |

No other callbacks.

### 8.3 `/cases/:slug/read[/:lead]`: `CaseLive.Read`

**Route/auth/layout:** public; two routes, same module: `/cases/:slug/read` and `/cases/:slug/read/:lead`. `Layouts.app` with **`bleed`**. `:lead` is a work slug.

**Mount** (`%{"slug" => slug} = params`): the case is looked up as in `Show`; missing gives flash `No such case.` and `push_navigate` to `/cases`. Found: assigns `case: c`, `only: nil` (relation filter), `source: nil` (document filter, a work id as string), `peek: nil` (a block ref), `walk: []`, `chat_open: false`, `chat_thinking: false`, `chat_mutter: []`, `chat_history: []`, `chat_cited: []`, then `load(socket, params["lead"])`.

**`handle_params(params, _uri, socket)`:** runs after mount and on every patch: calls `load(socket, params["lead"])` again; then if `params["walk"] == "1"` assigns `walk: Walkthrough.Cases.steps(:case_read)` (this is how the tour's third leg arrives: `/cases/:slug/read?walk=1`).

**`load(socket, lead_slug)`:** `lead = case.works |> find(slug == lead_slug) || Cases.default_lead(case)` (an unknown or absent lead slug silently falls back to the default lead; no 404). `reading = lead && Cases.reading(case, lead.id)`.

* `reading` nil (no works, or lead not in the case): assign `reading: nil`, `page_title: c.name`; no other meta changes.
* Otherwise assign `reading: r`, `page_url: url(~p"/cases/#{c.slug}/read/#{r.lead.slug}")`, `page_image: ~p"/images/og-cases.png"`, `page_title: "<lead.title> · read against the case"`, `page_description: "<lead.title>, read with <length(r.sources)> other documents from <case name> in the margin."` (`sources` includes documents from other cases).

**`Cases.reading(c, lead_id)`** returns nil if the lead is not in `c.works`; else:

* `inside`: links in `c.links` that touch the lead and whose `status == "linked"`, each `%{link, work: other_work, elsewhere: nil}`, sorted by `rank(other.collection_role)`.
* `elsewhere`: `Links.for_work(lead.id)` (newest first) with `status == "linked"`, other work non-nil with a non-nil `collection` different from this case's name, each `%{link, work, elsewhere: work.collection}`, sorted by `work.collection`.
* `sources = inside ++ elsewhere`.
* `notes`: for each source, `Links.margin(link, lead.id)` with `from_work` (other work id), `from_title` (other work's full title), `from_role`, `from_case`, `link_id` added.
* `page = Reading.page(lead, notes: notes)`.
* Result `%{lead, sources, notes, page}`.

**`Links.margin(link, lead_id)`** = `Links.notes_for(link, lead_id)` plus far-end data. `notes_for`: for each edge (via `Links.edges(link)`, rationale resolved) take `near` = the edge end in the lead work, `far` = the other end; keep it only if `near.section_id` is set and `near.quote` is non-blank. A note is `%{id: {:link, edge.id, near.id}, key: "link:<edge.id>", section_id: near.section_id, kind: edge.edge_type, quote: near.quote, title: "→ <far.title>" (when the edge starts at near) or "← <far.title>", body: edge.rationale, stale: false, edge_id: edge.id, peer: far.id}`. `margin` then adds `far_title`, `far_body`, `far_quote` (the far node's raw quote), `far_kind` (node type), `far_section` (the far node's section ordinal in the other work).

**`Reading.page(work, notes: notes)`:** for each section of the work (`Works.list_sections`, ordered by ordinal) group notes by `section_id`, split the section body into blocks (`Reading.split`: blank-line-separated markdown blocks, a fenced code block (``` or ~~~, any run length of 3+) is kept as one block regardless of blank lines inside it; blocks trimmed at the end; empty ones dropped), then place each note into the first block (in order) in which its `quote` can be located and which has not already placed it. A block is `%{text, mark, notes, ref}`: `mark` is the located span of the first placed note that has one (one highlight per block), `ref = "s<section.ordinal>p<index>"` (index is 0-based within the section). A section is `%{section, blocks, unplaced}`; `unplaced` is never rendered on these pages.

*Locating a quote* (`Analysis.Anchor.verify(quote, paragraph)`): trim the quote; fail if shorter than 8 characters; normalise both strings (collapse every run of whitespace, including NBSP and zero-width space, to one space; fold curly single quotes `‘ ’ ‛` to `'`, curly doubles `“ ”` to `"`, en/em dash to `-`, `…` to `...`; downcase everything else); find the normalised quote in the normalised paragraph; map the match back to a substring of the **original** paragraph through a per-grapheme index (`""` counts as not found). The result is a literal substring of the paragraph.

*Rendering a block* (`Reading.render_block(text, mark, ref)`): if `mark` is non-nil, find it in `text` (first occurrence by bytes), trim `* _ \` ~` characters off both ends of the matched span so that emphasis delimiters stay outside the highlight, surround the span with the private-use sentinels U+E000/U+E001, render with `Markdown.to_html(source, breaks: :soft)`, then replace the sentinels with `<mark id="anchor-<ref>">` and `</mark>`. If `mark` is nil/false the text is rendered with no mark. The result is raw HTML.

**Render** (the page `@reading` is nil means "nothing read yet"):

```heex
<Layouts.app flash={@flash} current_scope={@current_scope} bleed>
  <MarginaliaWeb.Walk.overlay
    :if={@walk != []}
    steps={@walk}
    note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
  />

  <MarginaliaWeb.LinkChat.bubble
    :if={@reading}
    open={@chat_open}
    history={@chat_history}
    thinking={@chat_thinking}
    mutter={@chat_mutter}
    count={length(@chat_history)}
    cited={cited_edges(@reading, @chat_cited)}
    title="About this case"
    label="Talk about how these documents sit together"
    hint={
      "This one holds every document in the case and every connection between the one " <>
        "you are reading and the rest. Ask what the dissent already answered, what the " <>
        "lectern settled, or which of the disagreements is real. It writes for none of them."
    }
    placeholder="How do these sit together?"
    openers={[
      "What did the dissent already answer?",
      "What did the advocates concede that the opinion then relied on?",
      "Where do these documents actually collide?"
    ]}
  />

  <%!-- What the rail opens. A sheet rather than a dialog: it comes
        from the edge the thumb is at, and the paragraph it belongs to
        stays visible above it. --%>
  <div :if={@peek && peeked(@reading, @peek) != []} class="cr-sheet-veil" phx-click="unpeek">
    <div class="cr-sheet" phx-click-away="unpeek">
      <div class="cr-sheet-head">
        <span class="mg-label">on this paragraph</span>
        <button phx-click="unpeek" aria-label="close">×</button>
      </div>
      <.note
        :for={n <- peeked(@reading, @peek)}
        note={n}
        rank={rank_id(@reading, n)}
        lead={@reading.lead}
        elsewhere={elsewhere(@reading, n)}
      />
    </div>
  </div>

  <div :if={is_nil(@reading)} class="cr-empty">
    <p>Nothing in <b>{@case.name}</b> has been read yet.</p>
    <.link navigate={~p"/cases/#{@case.slug}"} class="mg-btn">Back to the case</.link>
  </div>

  <div :if={@reading} class="cr">
    <div class="cr-bar">
      <div class="cr-bar-in">
        <div class="cr-who">
          <span class="mg-label">Reading…</span>
          <details class="cr-pick">
            <summary>
              <span class="t">{@reading.lead.title}</span>
              <span class="n">{length(@case.works)}</span>
            </summary>
            <div class="cr-pick-menu">
              <.link
                :for={w <- @case.works}
                patch={~p"/cases/#{@case.slug}/read/#{w.slug}"}
                class={["row", w.id == @reading.lead.id && "here"]}
              >
                <span class="t">{w.title}</span>
                <span class="r">{w.collection_role}</span>
              </.link>
            </div>
          </details>
        </div>

        <%!-- Which documents are speaking, and how loudly. The count is
            the useful half: it says which of the other documents this
            one is actually arguing with. --%>
        <div class="cr-srcs">
          <span class="mg-label">Against…</span>
          <button
            :for={{w, n} <- source_counts(@reading)}
            class={[
              "cr-chip",
              "s#{rank(w)}",
              w.collection != @case.name && "far",
              @source == to_string(w.id) && "on"
            ]}
            phx-click="source"
            phx-value-w={w.id}
            title={w.title}
          >
            <span class="t">{chip(w, @case.name)}</span>
            <span class="n">{n}</span>
          </button>
        </div>

        <div class="cr-kinds">
          <button
            :for={{k, n} <- kind_counts(@reading)}
            class={["cr-chip", "k-#{k}", @only == k && "on"]}
            phx-click="only"
            phx-value-k={k}
          >
            <span class="t">{String.replace(k, "_", " ")}</span>
            <span class="n">{n}</span>
          </button>
          <button :if={@only || @source} class="cr-clear" phx-click="clear">clear</button>
        </div>
      </div>
    </div>

    <div class="cr-grid">
      <%= for section <- @reading.page do %>
        <div class="cr-sechead">
          <span class="mg-label">Section {section.section.ordinal}</span>
          <h2>{section.section.title}</h2>
        </div>

        <%= for run <- condense(section.blocks, @only, @source) do %>
          <%= case run do %>
            <% {:gap, blocks} -> %>
              <%!-- Prose nothing else in the case touches. Folded, never
                    dropped: this is a reading view, and a reader must be
                    able to satisfy themselves that the quiet stretches
                    really are quiet. --%>
              <details class="cr-gap">
                <summary>
                  <span class="n">{length(blocks)} paragraphs</span>
                  <span class="w">{words(blocks)} words</span>
                  <span class="s">nothing else in the case touches this</span>
                </summary>
                <div :for={b <- blocks} class="cr-quiet">
                  {Reading.render_block(b.text, nil, b.ref)}
                </div>
              </details>
            <% {:block, block, notes} -> %>
              <div class={["cr-text", notes != [] && "linked"]} id={"b-#{block.ref}"}>
                {Reading.render_block(block.text, notes != [] && block.mark, block.ref)}
              </div>
              <% {shown, rest} = cap(notes) %>
              <div class={["cr-notes", notes == [] && "bare"]}>
                <.note
                  :for={n <- shown}
                  note={n}
                  rank={rank_id(@reading, n)}
                  lead={@reading.lead}
                  elsewhere={elsewhere(@reading, n)}
                />

                <%!-- A hub paragraph can draw eighteen notes, which makes
                      a grid row two thousand pixels tall beside four
                      lines of prose. The first few are spread across the
                      documents rather than taken in order, so a cap never
                      silently hides a whole source. --%>
                <%!-- Phone only: the notes collapse to one mark per
                      relation, still beside the paragraph, and the
                      reading itself gets the full width. --%>
                <button
                  :if={notes != []}
                  class="cr-rail"
                  phx-click="peek"
                  phx-value-ref={block.ref}
                  aria-label={"#{length(notes)} connections on this paragraph"}
                >
                  <span :for={n <- Enum.take(notes, 4)} class={["tick", "k-#{n.kind}"]}></span>
                  <span class="c">{length(notes)}</span>
                </button>

                <details :if={rest != []} class="cr-more">
                  <summary>{length(rest)} more on this paragraph</summary>
                  <.note
                    :for={n <- rest}
                    note={n}
                    rank={rank_id(@reading, n)}
                    lead={@reading.lead}
                    elsewhere={elsewhere(@reading, n)}
                  />
                </details>
              </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
  </div>
</Layouts.app>
```

and the note component:

```heex
<article class={["cr-note", "s#{@rank}", @elsewhere && "far"]}>
  <header>
    <span class="src">{short_title(@note.from_title)}</span>
    <span class={["rel", "k-#{@note.kind}"]}>{String.replace(@note.kind, "_", " ")}</span>
  </header>
  <%!-- A note from another case has to say so, or it reads as this
        case contradicting itself. --%>
  <p :if={@elsewhere} class="from">{@elsewhere}</p>
  <p class="why">{@note.body}</p>
  <%!-- The far end, in its own words. A note that says "this answers §4
        of the dissent" is a reference; one carrying the sentence is
        something you can actually read without leaving. --%>
  <blockquote :if={@note.far_quote}>{@note.far_quote}</blockquote>
  <footer>
    <span :if={@note.far_section}>§{@note.far_section}</span>
    <button phx-click="cite_edge" phx-value-edge={@note.edge_id} class="ask">
      talk about this
    </button>
    <.link navigate={~p"/links/#{@note.link_id}?lead=#{@lead.slug}"}>read the pair →</.link>
  </footer>
</article>
```

Notes on the render:

* The `<MarginaliaWeb.LinkChat.bubble>` call passes `mutter={@chat_mutter}`, `count={length(@chat_history)}`, `cited={cited_edges(@reading, @chat_cited)}` and the case-specific copy above (title `About this case`, label `Talk about how these documents sit together`, the hint and openers shown in the markup, placeholder `How do these sit together?`).
* `rank(work)` = index of `collection_role` in `["opinion","concurrence","dissent","argument"]`, else 9. It selects the colour class `s0..s9` (chips `s<rank>`, notes `s<rank>`). `rank_id(reading, note)` finds the source whose `work.id == note.from_work` and ranks that work (9 if none).
* `source_counts(r)`: for each of `r.sources` `{work, notes whose from_work == work.id}`; sources with zero notes are dropped. Chip text `chip(work, case.name)` is `short(work)` (the document name) when `work.collection == case.name`, else `work.collection`. Class `far` when the work belongs to another case. Chip title attribute is the work's full title.
* `kind_counts(r)`: `Enum.frequencies_by(notes, & &1.kind)` sorted by count descending. Label is `kind` with `_` replaced by a space.
* `elsewhere(r, note)` is the source's `elsewhere` string (the other case's name) for the source whose work produced the note, else nil. When set the note gets class `far` and an extra `<p class="from">`.
* `shown?(note, only, source)` = (`only` nil or `note.kind == only`) and (`source` nil or `to_string(note.from_work) == source`).
* `condense(blocks, only, source)` (per section): `kept` = the set of indexes `i-1, i, i+1` for every block `i` with at least one shown note; blocks are chunked into runs of consecutive same-membership; a run that is kept, or has length 1, yields one `{:block, block, shown_notes}` per block; any other run (2 or more unkept blocks) yields a single `{:gap, blocks}`.
* A gap renders `<details class="cr-gap">` with `n paragraphs` (`length`), `w words` (`words(blocks)`: whitespace-split token count summed), and the sentence `nothing else in the case touches this`; inside, each block's text rendered with no mark inside `div.cr-quiet`.
* A row is `div.cr-text(.linked if the block has any shown notes)#b-<ref>` followed by `div.cr-notes(.bare if no shown notes)`. The mark is only applied when the block has shown notes.
* `cap(notes)`: if 5 or fewer, all are shown, none folded. Otherwise group by `from_work` keeping the order of first appearance, round-robin interleave the groups (take the head of each group in turn until all are exhausted), and split after 5: the first five are shown, the rest go into `<details class="cr-more">` with summary `<n> more on this paragraph`.
* The phone rail (`button.cr-rail`) is always emitted for blocks with shown notes (CSS shows it only on narrow screens): `aria-label="<n> connections on this paragraph"`, up to 4 `span.tick.k-<kind>` for the first four notes, and `span.c` with the count. Click pushes `peek` with `ref`.
* `peeked(reading, ref)` finds the block with `to_string(b.ref) == to_string(ref)` anywhere in the page and returns **all** its notes (not filtered by `only`/`source`). The bottom sheet shows them; the veil click and the `×` and `phx-click-away` push `unpeek`.
* `Section <n>` heads come from `section.section.ordinal` and `.title`; there is no summary text.
* Inside `cr-pick` the case's works are listed as `patch` links to `/cases/:slug/read/:work_slug`: a patch, so `handle_params` re-runs `load` and filters/chat state persist across the change.

**Events and callbacks:**

| name | params | effect |
|---|---|---|
| `start_walk` | none | `walk = Walkthrough.Cases.steps(:case_read)` |
| `end_walk` | none | `walk = []` |
| `walk_hop` | any | `walk = []` (the tour's last leg is this page, so a hop here just ends it) |
| `only` | `k` | toggle `only` (relation filter) |
| `source` | `w` (work id string) | toggle `source` |
| `clear` | none | `only = nil`, `source = nil`, `peek = nil` |
| `toggle_chat` | none | flip `chat_open` |
| `cite_edge` | `edge` (id string) | `String.to_integer`; append to `chat_cited` if absent; `chat_open = true`; `peek = nil` |
| `uncite` | `edge` | remove the id from `chat_cited` |
| `chat_send` | `message` | trim; if empty, or `chat_thinking`, or `reading` is nil: no-op. Else `history = chat_history ++ [%{"role" => "user", "content" => text}]`, assign `chat_history`, `chat_thinking = true`, `chat_mutter = Marginalia.Mutterings.some(8)` (see 6.4), `chat_cited = []`, and `start_async(:chat, fn -> Cases.Chat.ask(reading, history, cited: cited_ids) end)` |
| `peek` | `ref` | `peek = ref` |
| `unpeek` | none | `peek = nil` |
| `handle_async(:chat, {:ok, {:ok, text}})` | | `chat_thinking = false`; append `%{"role" => "assistant", "content" => text}` to `chat_history` |
| `handle_async(:chat, {:ok, {:error, reason}})` | | `chat_thinking = false`; flash error `That did not go through: <inspect(reason)>` |
| `handle_async(:chat, {:exit, reason})` | | same flash with the exit reason |

**Not handled:** `close_chat`, which `LinkChat`'s hook pushes on any Escape keypress and on any mousedown outside the open panel. There is no clause for it in this module, so LiveView raises `FunctionClauseError`, the process dies, and the client remounts the page (losing `chat_history`, filters and the open panel). In the original app, pressing Escape on this page resets it. A rewrite should add a `close_chat` handler (`chat_open = false`); that is a behavioural fix, not a transcription.

No timers, PubSub or streams. The only server-initiated message is the async chat result.

**`Cases.Chat.ask(reading, history, cited: ids)`** (the model call): messages are, in order,

1. `{"role":"system","content": SYSTEM}` where SYSTEM is the text below,
2. `{"role":"system","content": card(reading)}`,
3. the chat history turns as stored,
4. optionally one `system` message built from the cited edges (`cited_card`).

Call: `LLM.chat(provider: nil, model: LLM.default_model(nil), effort: :low, temperature: 0.5, max_tokens: 4000, messages: messages)`. `{:ok, %{"content" => text}}` with non-empty text gives `{:ok, text}`; any other `{:ok, _}` gives `{:error, :empty_reply}`; `{:error, r}` passes through.

SYSTEM prompt, verbatim:

```
You are reading one document from a court case with every other document in that case
laid against it, and answering questions about how they sit together.

You are given the map of each document — every beat, the spine, the threads, the open
questions — and every connection drawn between the document being read and the others,
with the reason each was drawn. You do NOT have the full text of anything. Do not
pretend to.

HOW TO ANSWER
- Answer about the RELATIONSHIPS. "What does the opinion say about standing" is a
  question for one document; here the interesting questions are what these documents do
  to each other — what the dissent already answered, what the advocate conceded that the
  opinion then relied on, where two of them collide on the same paragraph.
- Name documents the way the reader sees them: "the dissent", "Gen. Sauer's argument",
  "the concurrence". Never by letter, and never by node number — those are plumbing.
- Quote only what you were given. Every beat arrives with the sentence it was anchored
  to; those are real and you may quote them. Anything else, say you do not have.
- A connection you were not given does not exist. If asked about one that is not in the
  list, say it was not drawn rather than inventing why it would have been.
- When a connection comes from a different case, say so. Two cases agreeing is a
  different claim from two documents in one case agreeing.
- Be short. Three tight paragraphs beat a page.

WHAT YOU DO NOT DO
- You do not write prose for any of these documents.
- You do not say which side should have won.
- You do not soften a real disagreement into "both make good points".
- You are not giving legal advice, and you do not pretend the reading is authoritative.
```

`card(reading)` (system message 2) is, with `name(w)` = title after `" — "`:

```
# THE DOCUMENT BEING READ

<name(lead)> — <lead.word_count> words

# READ AGAINST (<n sources>)

<for each source:  "- <name(work)> — <word_count> words" + (" (from <case>, a different case)" if elsewhere)
                    + (if link.summary: "\n    <Links.summary(link)>") >

# THE CONNECTIONS (<n edges>)

<for each {source, edge} over all sources (Links.edges(source.link)):
   "- <whose(from)> --<edge_type>--> <whose(to)>\n    <rationale>">

# MAP OF <NAME(LEAD) UPCASED>
<map(lead)>
<for each source: "\n# MAP OF <NAME UPCASED><from_case>\n<map(work)>">
```

where `whose(node)` is `<name(lead)>` if the node is in the lead, `<name(source.work)>` if in the source's work, else `another document`, then `" — " <> node.title`; and `map(work)` groups the work's nodes by `node_type` and prints, per type, `\n## <type>\n` followed by lines `- <title> (§<section ordinal>)` and, when the node has a quote, a second line `    "<quote with whitespace collapsed, first 160 chars>"`. The cited-edges message is `The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely.\n\n` followed, for each cited edge, by `## <EDGE TYPE UPCASED with spaces>[ (from <case>, a different case)]\nWhy it was drawn: <rationale>\n\n### <whose(from)>\n<Links.passage(from)>\n\n### <whose(to)>\n<Links.passage(to)>`.

**Tour steps for the other two legs** (`Walkthrough.Cases`):

`:follow` (shown on the pairwise reading, listed for completeness): `sides` ("Left is read. Right is the reference", target `.fl-colhead`, bottom); `follow` ("The right side follows you", `#fl-lead`, right); `wire` ("The line runs through the reason", `.fl-mid`, left); `filter` ("One kind of relation at a time", `.fl-legend`, bottom, act push `set_only` `{"only":"tension"}`); `filter_back` ("Everything, again", `.fl-legend`, bottom, act push `set_only` `{"only":"all"}`); `gaps` ("The quiet stretches are folded", `.fl-gap`, right); `chat` ("You can argue with it", `.lc`, left); `onward` ("Two documents is the pair. Now the whole case", `.fl-colhead`, bottom, act hop `case_read`).

`:case_read` (this page): 

1. `margin`: "The whole case in one margin". Body: "The dissent and every advocate, against the same paragraph, each saying which one it is. Reading the pairs separately is exactly what this hides — and the paragraphs where all of them speak at once are the ones worth having." Target `.cr-grid .cr-notes:not(.bare)`, `left`.
2. `row`: "A paragraph and its notes are one row". Body: "One hairline runs from the left edge of the paragraph, across the gutter, into its notes. They are level because the layout says so — there is no scrolling machinery here to drift." Target `.cr-text.linked`, `right`.
3. `who`: "Filter by who is speaking". Body: "Each chip is one of the other documents, with how often it has something to say. A dashed chip is another case in the term rather than another document in this one." Target `.cr-srcs`, `bottom`.
4. `lead`: "Read it from anyone's side". Body: "Any document in the case can be the one you read. The dissent with the majority in its margin is a different experience from the reverse, and both of them are the case." Target `.cr-pick`, `bottom`, act click `.cr-pick > summary`.
5. `done`: "That is the whole of it". Body: "Sixteen cases, eighty-two documents, each read on its own and then related. Every connection is anchored to a sentence in both documents, and anything that could not be found in both was discarded before it was stored." Target null, place `centre`.

(The `:follow` bodies are in `lib/marginalia/walkthrough/cases.ex`; they are owned by the pairwise reading page's spec.)

## 9. Drafts

"Public drafts" are all of the owner's works (`Works.public_drafts/0`: `works where user_id = owner.id order by inserted_at desc`; **including the documents that belong to cases**, since nothing filters on `collection`). A visitor's own uploads are never listed or served here: `Works.public_draft(slug)` is scoped to the owner's `user_id`. All three draft pages set `page_robots: "index, follow"`.

### 9.1 `/drafts`: `DraftLive.Index`

**Mount:** `drafts = Works.public_drafts()`; assigns `page_title: "Drafts"`, `page_description: "Drafts read end to end, with the notes that came out of reading them."`, `page_robots: "index, follow"`, `drafts`, `total: length(drafts)`. No `page_url`, so the canonical URL is the site root `/` (a quirk shared by the draft, linked and reading pages that omit `page_url`).

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="lx">
    <h1>Drafts</h1>
    <p class="lede">
      {@total} drafts, read end to end. Each one carries the notes that came out of
      reading it, in the margin beside the sentence that caused them.
    </p>

    <p :if={@drafts == []} class="mg-empty">Nothing here yet.</p>

    <ul class="mg-rows">
      <li :for={d <- @drafts}>
        <.link navigate={~p"/drafts/#{d.slug}"} class="t">{d.title}</.link>
        <p class="mg-meta">
          {d.word_count} words · {d.status}
        </p>
      </li>
    </ul>
  </div>
</Layouts.app>
```

`d.status` is the work's status string (`pending`, `reading`, `read`, `failed`). `{@total} drafts` is not singularised. No events, no `handle_params`.

### 9.2 `/drafts/:slug`: `DraftLive.Show`

**Mount** (`%{"slug" => slug}`): `Works.public_draft(slug)`. nil gives flash error `No such draft.` and `push_navigate` to `/drafts`. Found:

```elixir
assign(socket,
  page_title: work.title,
  page_description: String.slice(work.first_impression || work.title, 0, 300),
  page_robots: "index, follow",
  work: work,
  page: Reading.page(work),                    # see below
  changed: Works.revision_count(work.id))      # integer, count of rows in revisions
```

`Reading.page(work)` (no `notes:` option, no section filter) builds the margin from the draft's own graph: every node with `node_type == "beat"` becomes a note `%{kind: "beat", title: node.title, body: node.body, quote: node.quote, section_id: node.section_id}` (stale beats included), and every connection (`Works.all_connections(work.id)`: edges whose type is one of `develops pays_off requires tension realises asks_about` with both nodes present) whose **from** node is a beat with a section becomes a note `%{kind: <edge type>, title: "<label> <to.title>", body: edge.rationale, quote: from.quote}` where label is `develops →`, `pays off →`, `requires ←`, `tension with`, `realises`, `asks about`, or the raw type. Then sections, blocks, placement and `ref` are exactly as in 8.3 (`Reading.page`), block rendering is `Reading.render_block(b.text, b.mark, b.ref, nil)` (same markup, `<mark id="anchor-<ref>">`).

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="mx-auto max-w-5xl px-6 py-8">
    <div class="mg-meta">
      <.link navigate={~p"/drafts"}>← Drafts</.link>
    </div>

    <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight mt-2">
      {@work.title}
    </h1>
    <p class="mg-meta">
      {@work.word_count} words
      <span :if={@changed > 0}>
        ·
        <.link navigate={~p"/drafts/#{@work.slug}/changes"}>
          {@changed} change{if @changed == 1, do: "", else: "s"} since it arrived
        </.link>
      </span>
    </p>

    <div class="mg-read mt-6">
      <div class="mg-read-body">
        <%= for sec <- @page do %>
          <div class="mg-read-head">
            <div class="mg-label">Section {sec.section.ordinal}</div>
            <h2 style="font-family:var(--mg-serif)" class="text-[1.45rem] font-semibold mt-1">
              {sec.section.title}
            </h2>
            <div :if={sec.section.summary} class="mg-sum-text">{sec.section.summary}</div>
          </div>

          <div :for={b <- sec.blocks} class="mg-block" id={"block-#{b.ref}"}>
            {Reading.render_block(b.text, b.mark, b.ref, nil)}
          </div>
        <% end %>
      </div>

      <div class="mg-read-rail">
        <%= for sec <- @page, b <- sec.blocks, n <- b.notes do %>
          <div class={"mg-note-slot " <> n.kind} data-anchor={b.ref}>
            <div class={"mg-note " <> n.kind}>
              <span class="who">{String.replace(n.kind, "_", " ")}</span>
              <span class="said">{n.title}</span>
              <span :if={n.body} class="why">{n.body}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</Layouts.app>
```

Notes:

* There is **no hook** on this page. The sibling private page (`WorkLive.Show`) uses a hook that adds class `measured` to `.mg-read-rail` and absolutely positions each `.mg-note-slot[data-anchor]` level with its mark. Here nothing does, so the rail is a plain column to the right of the prose in document order, with every note of every section stacked from the top. This is the existing behaviour.
* Notes of a block appear in the order `b.notes` holds them (placement order: beats first, then connections, since `collect` concatenates `beat_notes ++ conn_notes`, then filtered by block).
* Unplaced notes (quote not found in any paragraph) are dropped silently.
* `Reading.render_block` output is trusted raw HTML (already sanitised by the Markdown step).
* `mg-sum-text` shows the section summary if the section has one (`sections.summary`).
* The `change{if @changed == 1, do: "", else: "s"}` expression yields `change` or `changes`: `1 change since it arrived`, `3 changes since it arrived`.

No events or callbacks.

### 9.3 `/drafts/:slug/changes`: `DraftLive.Changes`

**Mount:** `Works.public_draft(slug)`; nil gives flash `No such draft.`, navigate `/drafts`. Else:

```elixir
rows = Diff.rows(Works.baseline(work), work.body)
assign(socket,
  page_title: "#{work.title} — what changed",
  page_description: "Every change made to this draft, as a before and after.",
  page_robots: "index, follow",
  work: work, rows: rows, stat: Diff.stat(rows),
  revisions: Enum.reverse(Works.revisions(work.id)))   # newest first
```

`Works.baseline(work)`: if `work.baseline_body` is a non-empty string, that. Otherwise reconstruct: take `work.body` and fold the revisions newest first, replacing the first occurrence of `rev.after` with `rev.before` when `body` contains `rev.after` (a revision whose text is no longer present is skipped). `Works.revisions(id)`: all revision rows for the work ordered by `seq` asc; fields `seq`, `before`, `after`, `origin` (default `"edit"`), `note`, `section_ordinal`.

`Diff.rows(a_text, b_text)`:

1. `paragraphs(text)`: `nil` gives `[]`; replace `\r\n` with `\n`; split on `~r/\n{2,}/` dropping empties; trim each; drop empty strings.
2. LCS over the two paragraph lists where two paragraphs match when equal after collapsing `\s+` to one space and trimming (`key`).
3. Walk the LCS table from `(0,0)`: if both items match, emit `{:same, a_paragraph}` and advance both; else if `j < m` and (`i >= n` or `table[i][j+1] >= table[i+1][j]`) emit `{:ins, b_paragraph}` and advance `j`; else emit `{:del, a_paragraph}` and advance `i`.
4. `pair`: `{:same, p}` becomes `{:same, p, p}` (the "now" side shows the **earlier** version's whitespace). Each maximal run of consecutive non-same ops is split into its deletes (in order) and its inserts (in order) and zipped positionally with padding: both present gives `{:change, left, right}`, only left gives `{:del, left}`, only right gives `{:ins, right}`.

`Diff.words(left, right)` (= `Rewrite.diff`, changed in commit f0b2248 from an LCS table to Myers): tokenise each side with `~r/\S+\s*/` (a word and its trailing whitespace; nil is no tokens); compare tokens trimmed. If both sides have at least 200 tokens and the number of distinct trimmed tokens they share is below 5% of the smaller side's distinct-token count, the spans are "unrelated": the result is every left token as `:del` followed by every right token as `:ins`, merged into one `:del` and one `:ins`. Otherwise run `List.myers_difference/2` over the trimmed tokens (a minimal edit script; Elixir's implementation, whose tie-breaking a rewrite should reproduce by using the same Myers algorithm: deletions before insertions within a change) and map it back to the original tokens: `:eq` runs emit `{:same, token}` per word, where the token is the **new** side's token, except that when the new token has no trailing whitespace (end of paragraph) it is the trimmed new word plus the **old** token's trailing whitespace; `:del` runs emit `{:del, old_token}` each; `:ins` runs emit `{:ins, new_token}` each. Adjacent entries with the same op are merged by concatenating their text. Result `[{:same | :del | :ins, text}]`. (Commit fa1b141 also changed how a shared last word is handled; the `eq` rule above is the current behaviour. The paragraph-level `Diff.rows` LCS in `Marginalia.Diff` is unchanged.)

`Diff.stat(rows)` counts `same`, `changed` (`:change`), `added` (`:ins`), `removed` (`:del`). `Diff.any?(rows)` is true if any row is not `:same`.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="mg-diff">
    <div class="mg-meta">
      <.link navigate={~p"/drafts/#{@work.slug}"}>← {@work.title}</.link>
    </div>

    <div class="mg-diff-head">
      <span class="mg-label">Changes since it arrived</span>
      <span class="mg-meta ml-auto">
        {@stat.changed} edited · {@stat.added} added · {@stat.removed} removed
      </span>
    </div>

    <p :if={not Diff.any?(@rows)} class="mg-empty">
      Nothing has been changed yet.
    </p>

    <div :if={Diff.any?(@rows)} class="mg-diff-cols">
      <div class="mg-diff-colhead"><span>As it arrived</span><span>Now</span></div>

      <div :for={row <- @rows} class={"mg-diff-row " <> kind(row)}>
        <%= case row do %>
          <% {:same, l, _} -> %>
            <div class="side old">{l}</div>
            <div class="side new">{l}</div>
          <% {:change, l, r} -> %>
            <div class="side old">
              <span :for={{op, t} <- Diff.words(l, r)} class={klass(op, :old)}>{t}</span>
            </div>
            <div class="side new">
              <span :for={{op, t} <- Diff.words(l, r)} class={klass(op, :new)}>{t}</span>
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

    <div :if={@revisions != []} class="mg-diff-log">
      <div class="mg-label">Every change, newest first</div>
      <ol class="mg-rows">
        <li :for={rev <- @revisions}>
          <span class="n">{rev.seq}</span>
          <span class="mg-meta">
            {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
          </span>
          <div class="mg-diff-patch">
            <span :for={{op, t} <- Diff.words(rev.before, rev.after)} class={klass(op, :new)}>{t}</span>
          </div>
        </li>
      </ol>
    </div>
  </div>
</Layouts.app>
```

with helpers

```elixir
defp kind({:same, _, _}), do: "same"
defp kind({:change, _, _}), do: "change"
defp kind({:del, _}), do: "del"
defp kind({:ins, _}), do: "ins"

defp klass(:same, _), do: "w"
defp klass(:del, :old), do: "w del"
defp klass(:del, :new), do: "w hide"
defp klass(:ins, :old), do: "w hide"
defp klass(:ins, :new), do: "w ins"
```

Notes:

* Each `span` contains one diff token including its trailing whitespace; there is no extra whitespace between spans.
* In a `:change` row the left cell hides inserted words and strikes deleted ones; the right cell hides deleted words and highlights inserted ones.
* In the "Every change, newest first" log each patch is rendered with `klass(op, :new)`: so it shows the **after** text with insertions highlighted (`w ins`) and the deleted words present in the DOM but hidden (`w hide`). Deletions are not visible there.
* The `{if rev.note, do: " — #{rev.note}"}` renders nothing when the note is nil.

No events or callbacks.

## 10. Linked drafts

### 10.1 `/linked`: `LinkedLive.Index`

**Mount:**

```elixir
rows = Links.public_links()
assign(socket,
  page_title: "Linked drafts",
  page_description: "Pairs of drafts read against each other, with the edges between them: what develops what, what pays off what, and where they argue.",
  page_robots: "index, follow",
  rows: rows, total: length(rows),
  tensions: Enum.count(rows, &(&1.tensions > 0)),
  filter: "", limit: 40)
```

`Links.public_links/0` (cached, key `:public_links`, 5 min): owner nil gives `[]`. Else `Links.for_user(owner.id)` (every `Link` where either work belongs to the owner, `updated_at` desc, with `a_work`, `b_work` preloaded), plus two grouped queries: edge count per link and tension count per link (`edge_type == "tension"`); each becomes `%{link, edges, tensions}`; rows with `edges == 0` are dropped; sorted by `{-tensions, -edges}` (stable).

**Render:** `found = rows filtered by title; shown = Enum.take(found, limit)`, computed inside `render/1`. The filter keeps rows where the downcased `link.a_work.title` or `link.b_work.title` contains the downcased query (a plain substring; empty query keeps all).

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="lx">
    <h1>Linked drafts</h1>
    <p class="lede">
      Two drafts read against each other, with every edge the pass found: what develops
      what, what pays off a promise the other made, and where the two argue. The
      direction is part of the claim.
    </p>

    <p class="mg-meta">
      {@total} pairs · {@tensions} of them contain a tension, and those are first
    </p>

    <form phx-change="filter" id="lk-filter" class="lk-filter">
      <input
        type="text"
        name="q"
        value={@filter}
        placeholder="narrow by title — a case name, a chapter number"
        autocomplete="off"
      />
    </form>

    <p :if={@found == []} class="mg-empty">
      Nothing matches “{@filter}”.
    </p>

    <ul class="mg-rows">
      <li :for={r <- @shown} class={if r.tensions > 0, do: "has-tension", else: ""}>
        <.link navigate={~p"/linked/#{r.link.id}"} class="t">
          {r.link.a_work.title} ↔ {r.link.b_work.title}
        </.link>
        <p class="mg-meta">
          {r.edges} edges<span :if={r.tensions > 0} class="tension-count">
            · {r.tensions} tension{if r.tensions == 1, do: "", else: "s"}
          </span>
        </p>
      </li>
    </ul>

    <div :if={length(@found) > length(@shown)} class="lk-more">
      <button class="mg-btn sm" phx-click="more">
        Show {min(40, length(@found) - length(@shown))} more
        <span class="mg-meta">of {length(@found) - length(@shown)} left</span>
      </button>
    </div>
  </div>
</Layouts.app>
```

Notes:

* The empty-state message is shown whenever `found == []`, including when the query is empty, so with no public links at all the page shows `Nothing matches “”.` (curly quotes around the empty filter).
* The `li` class is `has-tension` when the row has any tension, else the empty string (`class=""` is emitted).
* The text `{r.tensions} tension{s}`: `1 tension`, `2 tensions`. The tension span's text starts with `· ` (middle dot, space).
* The "more" button text: `Show <min(40, left)> more` then `<span class="mg-meta">of <left> left</span>` where `left = length(found) - length(shown)`.
* The form is `phx-change="filter"`, no submit, no debounce.

**Events:**

| event | params | effect |
|---|---|---|
| `filter` | `q` | `filter = q`, `limit = 40` |
| `more` | none | `limit = limit + 40` |

### 10.2 `/linked/:id`: `LinkedLive.Show`

**Mount** (`%{"id" => id}`): `Links.public_link(id)`: owner exists, `Repo.get(Link, id)` with `a_work`, `b_work` preloaded, **both** works owned by the owner, and `edge_count(link.id) > 0`; else nil. nil gives flash error `No such pair.` and `push_navigate` to `/linked`. Found:

```elixir
edges = Links.edges(link)            # ordered ordinal asc, id asc; from/to nodes loaded; rationale A/B resolved
assign(socket,
  page_title: "#{a.title} ↔ #{b.title}",
  page_description: "#{length(edges)} edges between two drafts.",
  page_robots: "index, follow",
  link: link, grouped: group(edges), total: length(edges))
```

`group(edges)`: group by `edge_type`; order = `["tension", "answers", "pays_off", "develops", "requires", "echoes"]` followed by any other types present (in map-key order); keep only types that occur; each as `{type, [edges in original order]}`.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="lx">
    <div class="mg-meta">
      <.link navigate={~p"/linked"}>← Linked drafts</.link>
    </div>

    <h1>{@link.a_work.title} ↔ {@link.b_work.title}</h1>
    <p class="lede">
      {@total} edges. Each names a part of one draft and a part of the other, and the
      direction is part of the claim.
    </p>

    <p class="mg-meta">
      <.link navigate={~p"/drafts/#{@link.a_work.slug}"}>{@link.a_work.title}</.link>
      · <.link navigate={~p"/drafts/#{@link.b_work.slug}"}>{@link.b_work.title}</.link>
    </p>

    <section :for={{kind, edges} <- @grouped} class="lk-group">
      <h2 class="mg-label">{String.replace(kind, "_", " ")} · {length(edges)}</h2>

      <div :for={e <- edges} class={"lk-edge " <> kind}>
        <div class="lk-ends">
          <span class="from">{e.from && e.from.title}</span>
          <span class="arrow">{String.replace(kind, "_", " ")} →</span>
          <span class="to">{e.to && e.to.title}</span>
        </div>
        <p :if={e.rationale} class="why">{e.rationale}</p>
        <blockquote :if={e.from && e.from.quote} class="lk-quote">{e.from.quote}</blockquote>
      </div>
    </section>
  </div>
</Layouts.app>
```

`kind` with underscores replaced by spaces, so `pays_off` prints `pays off`. `e.from && e.from.title` prints nothing if the node is missing. The quote shown is the **from** node's raw `quote` only (not run through `Reading.plain`); the `to` quote is not shown. `.lk-edge` gets the type as a second class (`lk-edge tension`).

No events or callbacks.

## 11. Readings (published stacks)

A "reading" is a folder (`folders` row) with `published_at` set, a composed `Story`, and `Step`s. These pages need no owner and no account.

Shapes used:

* `Folder`: `id`, `name`, `slug`, `user_id`, `published_at`.
* `Story`: `title`, `opening` (markdown), `movements` (list of maps with keys `"heading"`, `"prose"` (markdown), `"turn"` (markdown, optional), `"steps"` (list of step ordinals)), `closing` (markdown).
* `Step`: `ordinal`, `capability`, `requires` (ordinals), `lesson`, `mechanism`, `pitfall`, `pitfall_quote`, `watch_for`, `revised_by` (ordinal), `revision`, `revision_quote`, `excerpts` (list of maps with `"text"` and optionally `"caption"`), `work_id`.

### 11.1 `/reading`: `ReadingLive.Index`

**Mount:**

```elixir
readings =
  Folders.published()                                   # all folders with published_at, newest published first
  |> Enum.map(fn f -> %{folder: f, story: Stacks.get_story(f.id), steps: Stacks.list_steps(f.id)} end)
  |> Enum.filter(& &1.story)                            # a folder with no composed story is hidden
assign(socket,
  page_title: "Readings",
  page_description: "Series of documents read forwards, so that what they add up to is a method somebody else can follow.",
  readings: readings)
```

No `page_robots`, no `page_url`.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="lx">
    <h1>Readings</h1>
    <p class="lede">
      A series of documents read <em>forwards</em> — each one told only what the ones
      before it established. Read that way, each says what somebody building the same
      thing must now do, and no single document contains it.
    </p>

    <p :if={@readings == []} class="mg-empty">Nothing published yet.</p>

    <ul class="mg-rows">
      <li :for={r <- @readings}>
        <.link navigate={~p"/reading/#{r.folder.slug}"} class="t">{r.story.title}</.link>
        <p class="mg-meta">
          {length(r.steps)} documents · {length(r.story.movements)} parts · {r.folder.name}
        </p>
      </li>
    </ul>
  </div>
</Layouts.app>
```

No events.

### 11.2 `/reading/:slug`: `ReadingLive.Story`

**Mount:** `Folders.get_published(slug)` (folder with that slug and non-null `published_at`) and `Stacks.get_story(folder.id)`. Either nil: flash error `No such reading.`, navigate `/reading`. Else:

```elixir
steps = Stacks.list_steps(folder.id)                    # ordered by ordinal
assign(socket,
  page_title: story.title || folder.name,
  page_description: String.slice(story.opening || "", 0, 300),
  folder: folder, story: story,
  steps: Map.new(steps, &{&1.ordinal, &1}),
  count: length(steps),
  mine?: mine?(folder, socket.assigns[:current_scope]))
```

`mine?`: true when `folder.user_id` is non-nil and equals the viewer's user id (the scope's user). The owner-only line is the sole difference between the viewer kinds.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <article class="st-story">
    <div class="mg-meta">
      <.link navigate={~p"/reading"}>← Readings</.link>
    </div>

    <h1>{@story.title}</h1>

    <p class="mg-meta">
      {@count} documents, read forwards. {@folder.name}
    </p>

    <p :if={@mine?} class="mg-meta st-yours">
      Yours. <.link navigate={~p"/stacks/#{@folder.id}"}>Open the folder</.link>
      to read it forwards again, compose it again, or get at any of the {@count} drafts.
    </p>

    <div class="lede md st-md">{Markdown.to_html(@story.opening)}</div>

    <section :for={{m, i} <- Enum.with_index(@story.movements, 1)} class="st-move">
      <h2><span class="n">{i}</span>{m["heading"]}</h2>
      <%!-- The model writes markdown whether or not anyone asked it to, and
            this prose is thick with identifiers in backticks. Rendered as
            plain text they show up as literal backticks. --%>
      <div class="md st-md">{Markdown.to_html(m["prose"])}</div>

      <aside :if={m["turn"] not in [nil, ""]} class="st-turn md st-md">
        {Markdown.to_html(m["turn"])}
      </aside>

      <nav :if={m["steps"] != []} class="st-move-steps">
        <span class="mg-label">from</span>
        <.link
          :for={n <- m["steps"]}
          navigate={~p"/reading/#{@folder.slug}/#{n}"}
          title={cap(@steps, n)}
        >{n}</.link>
      </nav>
    </section>

    <div class="st-closing md st-md">{Markdown.to_html(@story.closing)}</div>
  </article>
</Layouts.app>
```

`Markdown.to_html/1` with default hard breaks. `cap(steps, n)` is the step's `capability`, or `"step <n>"` if there is no such step; it is the link's `title` attribute. A movement without `"steps"` (nil) would crash the `:for`; a movement with `"steps": []` omits the nav.

No events.

### 11.3 `/reading/:slug/:ordinal`: `ReadingLive.Step`

**Mount:** all of: `Folders.get_published(slug)`; `Integer.parse(ordinal)` must be `{n, ""}`; `Stacks.guide(folder.id)`; an entry whose `step.ordinal == n`. Any failing: flash error `No such step.`, navigate `/reading`. Else:

```elixir
assign(socket,
  page_title: entry.step.capability,
  folder: folder, entry: entry, count: length(guide),
  story: Stacks.get_story(folder.id),
  source: source(entry, socket.assigns[:current_scope]))
```

No description (default pitch). `Stacks.guide(folder_id)`: for each step, `%{step, requires: [steps named in step.requires that exist], required_by: [...], previous: step with ordinal-1 or nil, next: step with ordinal+1 or nil}` (neighbours are by ordinal arithmetic, so a gap in ordinals gives no link). `source/2`: when the viewer has a user and `step.work_id` is non-nil, `Works.get_work(user.id, work_id)` (owner-scoped lookup, so only the work's owner gets a non-nil result), else nil. This is how the owner gets a "yours" line without leaking draft slugs.

**Render:**

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <article class="st-step">
    <div class="mg-meta">
      <.link navigate={~p"/reading/#{@folder.slug}"}>← {(@story && @story.title) || @folder.name}</.link>
    </div>

    <span class="n">Step {@entry.step.ordinal} of {@count}</span>
    <h1>{@entry.step.capability}</h1>

    <p :if={@source} class="mg-meta st-yours">
      Read out of <.link navigate={~p"/works/#{@source.slug}?view=read"}>{@source.title}</.link>,
      which is yours to edit.
    </p>

    <section :if={@entry.step.lesson}>
      <h2 class="mg-label">What to do</h2>
      <div class="md st-md">{Markdown.to_html(@entry.step.lesson)}</div>
    </section>

    <section :if={@entry.step.mechanism}>
      <h2 class="mg-label">How it works</h2>
      <div class="md st-md">{Markdown.to_html(@entry.step.mechanism)}</div>
    </section>

    <section :if={@entry.step.pitfall not in [nil, ""]} class="st-pitfall">
      <h2 class="mg-label">The obvious version is wrong</h2>
      <div class="md st-md">{Markdown.to_html(@entry.step.pitfall)}</div>
      <blockquote :if={@entry.step.pitfall_quote not in [nil, ""]}>
        {@entry.step.pitfall_quote}
      </blockquote>
    </section>

    <section :if={@entry.step.watch_for}>
      <h2 class="mg-label">Get right now</h2>
      <div class="md st-md">{Markdown.to_html(@entry.step.watch_for)}</div>
    </section>

    <section :if={@entry.step.revised_by} class="st-revision">
      <h2 class="mg-label">Walked back by step {@entry.step.revised_by}</h2>
      <div class="md st-md">{Markdown.to_html(@entry.step.revision)}</div>
      <blockquote :if={@entry.step.revision_quote not in [nil, ""]}>
        {@entry.step.revision_quote}
      </blockquote>
    </section>

    <section :if={@entry.step.excerpts != []}>
      <h2 class="mg-label">From the document</h2>
      <%!-- "text" is the passage the quote was located in, not the model's
            quote: validate/3 stores the surrounding block so a reader sees
            the claim in its context rather than the sentence alone. --%>
      <figure :for={e <- @entry.step.excerpts} class="st-excerpt">
        <pre><code>{e["text"]}</code></pre>
        <figcaption :if={e["caption"] not in [nil, ""]}>{e["caption"]}</figcaption>
      </figure>
    </section>

    <nav :if={@entry.requires != []} class="st-move-steps">
      <span class="mg-label">stands on</span>
      <.link :for={r <- @entry.requires} navigate={~p"/reading/#{@folder.slug}/#{r.ordinal}"}>
        {r.ordinal}
      </.link>
    </nav>

    <nav class="st-nav">
      <.link
        :if={@entry.previous}
        navigate={~p"/reading/#{@folder.slug}/#{@entry.previous.ordinal}"}
      >
        ← {@entry.previous.ordinal}. {@entry.previous.capability}
      </.link>
      <.link :if={@entry.next} navigate={~p"/reading/#{@folder.slug}/#{@entry.next.ordinal}"}>
        {@entry.next.ordinal}. {@entry.next.capability} →
      </.link>
    </nav>
  </article>
</Layouts.app>
```

Notes:

* `:if={@entry.step.lesson}` and `:if={@entry.step.mechanism}` and `:if={@entry.step.watch_for}` test truthiness only: an empty string is truthy in Elixir, so an empty (but not nil) value still renders an empty section. `pitfall` and the quotes are tested with `not in [nil, ""]`. `revised_by` is an integer ordinal or nil.
* The heading `Walked back by step <n>` uses `revised_by` as the number; there is no link.
* The step text in `<pre><code>` is `excerpt["text"]` (the passage the quote was found in).
* `stands on` links print the ordinal only.

No events.

## 12. Index of server interaction

Pages with live events: landing (1), `/cases` (2), `/cases/:slug` (6), `/cases/:slug/read` (12 `handle_event`, 3 `handle_async`, 1 `handle_params`), `/linked` (2). The other pages (`/drafts`, `/drafts/:slug`, `/drafts/:slug/changes`, `/linked/:id`, `/reading*`) are read-only renders with no events. Total `handle_event` clauses: 23 (names: `toggle_notes`; `impression`, `walk_hop`; `search`, `kind`, `pair`, `clear`, `open`, `toggle_docs`; `start_walk`, `end_walk`, `walk_hop`, `only`, `source`, `clear`, `toggle_chat`, `cite_edge`, `uncite`, `chat_send`, `peek`, `unpeek`; `filter`, `more`). Events pushed by hooks or components that a host page does not handle: `close_chat` (from `.LinkChat`; unhandled on `/cases/:slug/read`), `end_walk` (from `.Walk` in non-auto mode; handled there), `relink` (from `LinkWaiting`; not rendered in this scope).

Server-initiated pushes: only the `:chat` async result on `/cases/:slug/read`. No PubSub subscriptions, no `handle_info`, no timers or streams anywhere in scope. Client-side timers: `.Rotate` swaps a line every 3 s, `.Walk` re-measures every 250 ms, `.Wiring` draws an arc every 900 ms, `.Reveal` schedules per-step timeouts.

Colocated hooks in scope: `.Reveal` (landing), `.Walk` (case index, case read), `.LinkChat`, `.Composer`, `.StickDown`, `.Rotate` (case read, via `LinkChat.bubble` and `<.mutter>`; `.Rotate` is defined in `core_components.ex`), `.Wiring` (defined in `LinkWaiting`, unused by these pages). `test/marginalia_web/hooks_test.exs` enforces that every `phx-hook=".X"` has a matching `ColocatedHook name=".X"` in the same module and vice versa, and that every `this.method()` a hook calls is defined in it; a rewrite that keeps hooks as separate JS files should keep an equivalent check.

## 13. Things that behave unexpectedly (as the code stands)

1. **`/cases/:slug/read` crashes on Escape.** `.LinkChat` pushes `close_chat` on every `Escape` keydown on the document, and on any mousedown outside the open panel; `CaseLive.Read` has no `close_chat` clause. The LiveView process raises and the client remounts the page: chat history, filters and the open panel are lost. (The pairwise reading, `LinkLive.Read`, does handle it.)
2. **The sitemap namespace is misspelled**: `http://www.sitemap.org/schemas/sitemap/0.9`, not `sitemaps.org`.
3. **The public draft page does not align notes with paragraphs.** `.mg-read-rail` has no positioning hook on `/drafts/:slug`; all notes stack from the top of the right column. Only the owner's private page measures and aligns them.
4. **Raw versus resolved rationale.** On `/cases` the "hook" sentence and the "for instance" opener use the raw edge rationale (may contain bare "A"/"B"/"Manuscript A"); `/cases/:slug`, `/linked/:id` and the reading notes use `Links.edges/1` which resolves those to document names.
5. **The anonymous scope is `nil`, not an empty scope.** `Scope.for_user(nil)` returns `nil`; templates test `@current_scope && @current_scope.user`.
6. **`/drafts` is not "drafts only".** It lists every work the owner has, which includes every document of every case.
7. **Canonical URL and card defaults.** `/drafts`, `/drafts/:slug`, `/drafts/:slug/changes`, `/linked`, `/linked/:id`, `/reading`, `/reading/:slug` and `/reading/:slug/:ordinal` set no `page_url`, so their `<link rel="canonical">` and `og:url` point at the site root `/`. `/cases` sets title, description, image, image alt and url; `/cases/:slug` sets title, url and image only (so its image alt is the site card's and its description is the product pitch); `/cases/:slug/read` sets title, description, url and image.
8. **Plural and empty-state slips.** `1 drafts`, `1 Supreme Court cases`, `1 connections` (case page ways), and `Nothing matches “”.` on `/linked` when there are no public links at all.
9. **`/cases` repeats the opinion's impression twice per case** (a clamped paragraph with a more/less button, and a `<details>`), and shows only the first three pairings per case while `/cases/:slug` lists all links including empty ones.
10. **The `Changes` log hides deletions** (`w hide` on removed words) so each entry shows only the new text with insertions highlighted.
11. **`walk_hop` with any `to` other than `first_pair` crashes `/cases`** (no fallback clause).
12. **`/cases/:slug/read` runs its loader twice on mount** (`mount` and `handle_params`), and its chat history survives a `patch` to a different lead document while the `reading` it describes changes.
13. **Remember-me is honoured only by the HTTP plug.** The LiveView `on_mount` reads `session["user_token"]` only; it works because the plug has already copied the cookie's token into the session before the page renders.
14. **A reissued session token does not delete the old one**; both live until the 14-day expiry. Guests get no remember-me cookie.
15. **Nothing in the public UI changes the theme.** The theme script reads `localStorage["phx:theme"]`; `theme_toggle` is defined but not rendered.
16. **The landing page cannot show flash messages** (no `Layouts.app`); it hard-codes four production slugs.
17. **Freshness reload** appends `_fresh=1` to the URL and does a full navigation; the parameter stays in the address bar.
18. **`/sitemap.xml` is in the `:browser` pipeline** (`accepts ["html"]`) and therefore 406s for clients whose `Accept` header excludes `text/html` and `*/*`.

## 14. Tests that pin this behaviour

`test/marginalia_web/`: `error_page_test.exs`, `og_test.exs`, `sitemap_test.exs`, `user_auth_test.exs`, `hooks_test.exs`; `live/`: `landing_live_test.exs`, `landing_features_test.exs`, `case_index_test.exs`, `case_page_test.exs`, `case_read_test.exs`, `cases_tour_test.exs`, `public_drafts_test.exs`, `public_changes_test.exs`, `public_linked_test.exs`, `public_reading_test.exs`, `linked_index_test.exs`, `link_chat_flow_test.exs`. These assert on markup fragments and are the best oracle for a byte-for-byte rewrite.

## 15. Data extracts shipped with this file

* `blimp/notes/web-public-extracts/landing.css`, `landing-body.heex`, `landing-reveal-hook.js`: the landing page, verbatim.
* `blimp/notes/web-public-extracts/cases-record.ex`: the `@records` map (docket, argued, decided, optional question per case name) from `Marginalia.Cases.Record`.
