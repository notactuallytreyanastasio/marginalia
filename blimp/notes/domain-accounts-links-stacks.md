# Marginalia domain layer: accounts, folders, links, cuts, stacks, cases, import, git, LLM

Specification for a port to Temper. Source of truth is the Elixir in
`/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/lib/marginalia/` at HEAD `81161a8`, read directly.
Test files in `test/marginalia/` are cited for examples.

## 0. Provenance and things that are not where you expect

* **Mutterings do not exist in this worktree.** `lib/marginalia/mutterings*`, their migrations, and
  `Marginalia.Mutterings.Clock` exist only on branch `main` (commits `832ccc4`..`a196fc6`). Section 10 is written from
  `git show main:...`. `main` also adds `Import.Bulk.folder_name_for/2` and `Import.Bulk.in_name_order/1` (section 9.4)
  and one line in `application.ex`. Everything else in this document is identical on both.
* **There is no `git clone` anywhere.** `Marginalia.Git` only does `git init`, `commit`, `log`, `show` on a local
  per-draft repository (section 9.7). Nothing is cloned and nothing is cleaned up.
* **Guests are never cleaned up.** No code deletes a guest user or any token (section 2.6).
* **Prod mail is the in-memory `Swoosh.Adapters.Local`**; nothing is delivered (section 2.8).
* **No tool loops.** `Links.Chat` and `Cases.Chat` pass no tools; they are single `LLM.chat` calls. The only tool use is
  forced/auto single-tool "structured output" via `LLM.call_tool/1`.
* **No streaming** anywhere in `LLM`. One blocking POST per call.
* Several functions call modules outside the assigned scope (`Works`, `Works.Upload`, `Reading`, `Document`,
  `Analysis`, `Analysis.Linker`, `Chat`). Their contracts as used here are given where they matter; their prompts are
  not reproduced.
* Elixir heredocs: a trailing `\` at end of line joins the next line with no newline. Prompts in section 13 are
  given with those joins already resolved. Every heredoc ends with exactly one trailing `\n`.
* Time columns are `utc_datetime` (second precision, `timestamp(0) without time zone`). IDs are `bigserial`.
  Postgres via Ecto/Postgrex. "jsonb" means an Ecto `:map` column.

---

## 1. Data model

### 1.1 `users`
| column | type | null | default | notes |
|---|---|---|---|---|
| id | bigserial PK | | | |
| email | **citext** | no | | extension `citext` created (`CREATE EXTENSION IF NOT EXISTS citext`). Case-insensitive comparison and uniqueness |
| hashed_password | varchar(255) | yes | | bcrypt string |
| confirmed_at | utc_datetime | yes | | |
| is_admin | boolean | no | false | |
| llm_provider | varchar(255) | yes | | |
| is_guest | boolean | no | false | |
| seen_tours | varchar(255)[] | no | `{}` | |
| inserted_at, updated_at | utc_datetime | no | | |

Indexes: unique `users(email)`; `users(is_guest)`.
Schema-only (virtual) fields: `password` (redacted), `authenticated_at` (utc_datetime, filled from the session token on lookup).

### 1.2 `users_tokens`
| column | type | null | notes |
|---|---|---|---|
| id | bigserial PK | | |
| user_id | bigint FK users, ON DELETE CASCADE | no | |
| token | bytea | no | session tokens: raw 32 bytes. emailed tokens: SHA-256 digest (32 bytes) |
| context | varchar | no | `"session"`, `"change:<email>"`, (`"login"` defined but unused) |
| sent_to | varchar | yes | |
| authenticated_at | utc_datetime | yes | |
| inserted_at | utc_datetime | no | no `updated_at` |

Indexes: `users_tokens(user_id)`; unique `users_tokens(context, token)`.

### 1.3 `folders`
| column | type | null | default |
|---|---|---|---|
| id | bigserial PK | | |
| name | varchar(255) | no | |
| user_id | FK users ON DELETE CASCADE | no | |
| parent_id | FK folders ON DELETE SET NULL | yes | |
| published_at | utc_datetime | yes | NULL = private |
| slug | varchar(255) | yes | |
| inserted_at/updated_at | | no | |

Indexes: `folders(user_id)`, `folders(parent_id)`, unique partial `folders_sibling_name_index` on `(user_id, parent_id, name) WHERE parent_id IS NOT NULL`,
unique partial `folders_root_name_index` on `(user_id, name) WHERE parent_id IS NULL`, unique `folders(slug)` (NULLs distinct), `folders(published_at)`.
`works.folder_id` (FK folders ON DELETE SET NULL, indexed) is the membership column. Names are case-sensitive in the unique indexes.

Ecto associations: `belongs_to user`, `belongs_to parent`, `has_many children` (fk parent_id), `has_many works`.

### 1.4 `links`
`id`; `a_work_id`, `b_work_id` bigint FK works ON DELETE CASCADE not null; `status` varchar(255) not null default `'pending'`;
`summary` text; `error` varchar(255) (**255 limit; see surprise S4**); timestamps.
Indexes: unique `(a_work_id, b_work_id)`, `(b_work_id)`. CHECK `links_are_between_two_works`: `a_work_id <> b_work_id`.
Invariant maintained in code: `a_work_id < b_work_id`. Status values (validated): `pending linking linked failed`.

### 1.5 `link_edges`
`id`; `link_id` FK links CASCADE not null; `from_id`, `to_id` FK nodes CASCADE not null; `edge_type` varchar not null;
`rationale` text; `ordinal` integer not null default 0; timestamps.
Indexes: unique `(link_id, from_id, to_id, edge_type)`, `(link_id, ordinal)`, `(from_id)`, `(to_id)`.
Edge types accepted when storing (`Linker.types/0`): `develops pays_off requires tension answers echoes`.

### 1.6 `cuts` (a "reading" of a folder)
`id`; `title` varchar not null; `question` text; `status` varchar not null default `'draft'`; `status_detail` text;
`thesis` text; `threads` jsonb; `tensions` jsonb; `not_supported` text; `dropped` jsonb; `content_sha` varchar;
`user_id` FK users CASCADE not null; `folder_id` FK folders SET NULL; `scope` varchar not null default `'folder'`;
`members` jsonb; timestamps.
Indexes: `cuts(user_id)`, `cuts(folder_id)`, unique partial `cuts_one_per_folder_index` on `(user_id, folder_id) WHERE folder_id IS NOT NULL`.
Despite the `:map` column type, the schema stores **JSON arrays** (`{:array, :map}` for threads/tensions/members, `{:array, :string}` for dropped); defaults `[]`.
`cut_picks` was created (20260918010000) and dropped (20260918030000); it does not exist.
Status values: `draft reading read failed` (validated on changeset only for `changeset/2` and `result_changeset/2`; `set_status/3` bypasses validation).

### 1.7 `stack_steps`
`id`; `folder_id` FK folders CASCADE not null; `work_id` FK works CASCADE not null; `ordinal` integer not null;
`capability` text; `requires` integer[] default `{}`; `lesson` text; `pitfall` text; `pitfall_quote` text; `excerpts` jsonb (array of `{"caption","text"}`);
`fingerprint` varchar; `dropped` varchar[] default `{}`; `mechanism` text; `watch_for` text; `revised_by` integer; `revision` text; `revision_quote` text;
`deep_dropped` varchar[] default `{}`; `deepened_at` utc_datetime; timestamps.
Indexes: unique `(folder_id, work_id)`, `(folder_id)`. There is **no** unique on `(folder_id, ordinal)`.

### 1.8 `stack_stories`
`id`; `folder_id` FK folders CASCADE not null; `title` text; `opening` text; `movements` jsonb (array of `{"heading","prose","steps":[int],"turn"}`);
`closing` text; `uncovered` integer[] default `{}`; `dropped` varchar[] default `{}`; `fingerprint` varchar; timestamps. Unique `(folder_id)`.

### 1.9 `mutterings` (main only)
`id`; `text` text not null; `source` varchar not null default `'cron'`; timestamps. Unique `mutterings(text)` (a migration first deletes duplicates keeping lowest id).

### 1.10 Tables outside scope that this layer reads or writes
* `works`: `id, user_id, slug (unguessable, unique, 16 random bytes url-b64), title, intent, body, baseline_body, word_count, status (pending|reading|read|failed), status_detail, first_impression, source_url, collection, collection_role, folder_id, derived_from_id`.
* `sections`: `id, work_id, ordinal, title, body, word_count, status, summary, ...`.
* `nodes`: `id, work_id, section_id, node_type (beat|spine|thread|question|goal|...), title, body, quote, ordinal, status, narrative`.
* `document_summaries(work_id, summary, ...)` (via `Works.DocumentSummary`, counted in `Stacks.stats`).
* `conversations` once had `link_id`; the migration series nets out to "conversations belong only to a work".

### 1.11 Changesets (verbatim rules)
**User.email_changeset(user, attrs, opts)**: cast `[:email]`; required; format `~r/^[^@,;\s]+@[^@,;\s]+$/` message `"must have the @ sign and no spaces"`;
length max 160. If `opts[:validate_unique]` (default true): `unsafe_validate_unique(:email, Repo)` (error `"has already been taken"`), `unique_constraint(:email)`,
and `validate_email_changed`: if the effective email is set and there is no change, add error on `:email` `"did not change"`.
**User.password_changeset(user, attrs, opts)**: cast `[:password]`; `validate_confirmation(:password, message: "does not match password")` (only checks when a `password_confirmation` key is supplied);
required; length min 12, max 72 (characters). If `opts[:hash_password]` (default true) and a password change exists and the changeset is valid:
also length max 72 **bytes** (`count: :bytes`), then `hashed_password = Bcrypt.hash_pwd_salt(password)` and the `password` change is deleted.
Ecto stock messages apply: `"can't be blank"`, `"should be at least %{count} character(s)"`, `"should be at most %{count} character(s)"`, `"should be at most %{count} byte(s)"`.
**User.confirm_changeset**: sets `confirmed_at = now (second)`.
**Folder.changeset(folder, attrs)**: cast `[:name, :parent_id]`; trim `name`; required name; length max 80; two `unique_constraint(:name)` with `name: :folders_sibling_name_index` and `:folders_root_name_index`, both message `"there is already a folder with that name here"`.
**Link.changeset**: cast `[:a_work_id,:b_work_id,:status,:summary,:error]`; required `a_work_id,b_work_id`; status in `pending linking linked failed`; `check_constraint(:a_work_id, name: :links_are_between_two_works)`; `unique_constraint([:a_work_id,:b_work_id])`.
**LinkEdge.changeset**: cast `[:link_id,:from_id,:to_id,:edge_type,:rationale,:ordinal]`; required `link_id,from_id,to_id,edge_type`; `unique_constraint([:link_id,:from_id,:to_id,:edge_type])`.
**Cut.changeset**: cast `[:title,:question,:folder_id,:status,:status_detail,:scope]`; trim title; required title; length max 200; status in `draft reading read failed`.
**Cut.result_changeset**: cast `[:thesis,:threads,:tensions,:not_supported,:dropped,:content_sha,:status,:members]`; status inclusion.
**Stacks.Step.changeset**: cast `[:folder_id,:work_id,:ordinal,:capability,:requires,:lesson,:pitfall,:pitfall_quote,:excerpts,:fingerprint,:dropped]`, no validations.
**Step.deep_changeset**: cast `[:mechanism,:watch_for,:revised_by,:revision,:revision_quote,:deep_dropped,:deepened_at]`; required `folder_id,work_id,ordinal`; `unique_constraint([:folder_id,:work_id])`.
**Story.changeset**: cast `[:folder_id,:title,:opening,:movements,:closing,:uncovered,:dropped,:fingerprint]`; required `folder_id`; `unique_constraint(:folder_id)`. `Story.complete?(story)` = `uncovered in [nil, []]`.

---

## 2. Accounts (`accounts.ex`, `accounts/*`)

Auth is **password only**. No magic-link login, no password-reset flow, no email confirmation on registration.

### 2.1 Password hashing
`bcrypt_elixir 3.3.2`: `Bcrypt.hash_pwd_salt(password)` = bcrypt `$2b$`, 16-byte random salt, **log_rounds 12** (library default; config sets `:bcrypt_elixir, :log_rounds, 1` only in test).
Verify: `Bcrypt.verify_pass(password, hashed)`. If there is no user, no hash, or empty password: `Bcrypt.no_user_verify()` (a dummy hash comparison, for timing) and return false. 72-byte password cap is enforced in the changeset.

### 2.2 Tokens
* **Session token**: `strong_rand_bytes(32)` stored **raw** in `users_tokens.token`, `context="session"`, `authenticated_at = user.authenticated_at || now(second)`, `user_id`, `inserted_at`. The raw bytes go into the signed Phoenix session/remember-me cookie. Validity: `inserted_at > now - 14 days` (query enforced). Lookup `get_user_by_session_token(token)` returns `{user_with_authenticated_at_set_from_token, token.inserted_at}` or `nil`.
* **Emailed token** (`build_email_token(user, context)`): 32 random bytes; stored `token = SHA-256(raw)`, `context`, `sent_to = user.email` of the struct passed in; returned to the caller as `Base64url(raw, no padding)`. Verified by base64url-decode (failure -> `:error`), SHA-256, lookup by `(hash, context)`.
  * `"change:<email>"` context: valid 7 days. Used.
  * `"login"` (magic link): valid 15 minutes and requires `sent_to == user.email`. **Defined in `UserToken` but no `Accounts` function builds or consumes it.** Do not port unless wanted.
* Web layer (not in scope but relevant): cookie max age 14 days, session token reissued when older than 7 days, remember-me cookie `_marginalia_web_user_remember_me` signed, same-site Lax.

### 2.3 Public functions
| function | behavior |
|---|---|
| `get_user_by_email(email)` | `users` where email = email (citext, case-insensitive) -> user or nil |
| `get_user_by_email_and_password(email, pw)` | fetch by email; return user iff `valid_password?`; else nil |
| `get_user!(id)` | by id; raises `Ecto.NoResultsError` |
| `register_user(attrs)` | `email_changeset(attrs)` (unique validation on) + `password_changeset(attrs)`; sets `confirmed_at = now(second)`; insert. `{:ok, user}` or `{:error, changeset}` |
| `change_user_registration(user \\ %User{}, attrs \\ %{})` | email_changeset `validate_unique: false` + password_changeset `hash_password: false` (form validation) |
| `create_guest_user()` | see 2.6 |
| `claim_guest_account(%User{is_guest: true}=u, attrs)` | `email_changeset(attrs)` + `password_changeset(attrs)` (hashing on) + `is_guest=false`, `confirmed_at=now`; update the same row. Non-guest: returns `{:error, user}` (not a changeset) |
| `sudo_mode?(user, minutes \\ -20)` | true iff `user.authenticated_at` is a DateTime and is after `now + minutes minutes`. Else false. The settings page calls it with default (-20); `:require_sudo_mode` on_mount uses -10 |
| `change_user_email(user, attrs, opts)` | `email_changeset` |
| `deliver_user_update_email_instructions(user, current_email, url_fun)` | builds email token with context `"change:#{current_email}"` for `user` (callers pass the user with the **new** email applied, so `sent_to` = new email), inserts the token, calls `UserNotifier.deliver_update_email_instructions(user, url_fun.(encoded_token))`. Returns `{:ok, email}` or error from Mailer |
| `update_user_email(user, token)` | context = `"change:#{user.email}"`. In one transaction: verify token query (7 days) -> row; update email to `row.sent_to` via `email_changeset` (unique + did-not-change checks apply); delete all of that user's tokens in that context. Any failure -> `{:error, :transaction_aborted}`; success `{:ok, user}` |
| `change_user_password(user, attrs, opts)` | `password_changeset` |
| `update_user_password(user, attrs)` | password_changeset + update, then **delete all tokens of the user** (every context) in one transaction. Returns `{:ok, {user, tokens_deleted_list}}` (caller disconnects sockets) or `{:error, changeset}` |
| `generate_user_session_token(user)` | insert session token, return raw 32 bytes |
| `get_user_by_session_token(token)` | see 2.2 |
| `delete_user_session_token(token)` | delete rows `(token, "session")`; returns `:ok` |
| `owner?(user)` | `lower(user.email) == lower(owner_email)`; false for non-binary email. Config `:owner_email` (env `OWNER_EMAIL`, default `"bobbbygrayson@gmail.com"`) |
| `owner()` | the user whose `lower(email)` equals `lower(owner_email)`, or nil (also nil if owner_email is `""`) |
| `provider_for(user)` | `user.llm_provider` iff it is a non-empty string AND `owner?(user)`; else nil (meaning "use deploy default") |
| `set_llm_provider(user, provider)` | non-owner: `{:ok, user}` unchanged (silent no-op); owner with provider not in `["deepseek","openai"]` -> `{:error, :unknown_provider}`; else update `llm_provider` |
| `seen_tour?(user, view)` | `to_string(view) in user.seen_tours`; anything else (not a user / non-list) -> true |
| `mark_tour_seen(user, view)` | if already present `{:ok, user}`; else update `seen_tours = uniq([view | seen_tours])` (prepends) |

`Scope` is a struct `{user}`; `for_user(%User{})` -> scope, `for_user(nil)` -> nil. Config marks it the default scope (`assign_key :current_scope`, `access_path [:user, :id]`).

### 2.4 Admin
`is_admin` is only ever set by `Release.make_admin(email)` (section 12.3). The app reads it in exactly one place (work page `admin?` assign). Admin confers no provider choice: only the **owner** may switch backends (test `provider_gate_test`).

### 2.5 Provider choice
Per-user `llm_provider` is honoured only for the owner. Callers pass `provider: Accounts.provider_for(user)` into `LLM` calls; nil means deploy default (`LLM_PROVIDER`, default deepseek).

### 2.6 Guests
* Minted lazily by the web plug `ensure_user_or_guest` on routes that allow anonymous use (not in the global pipeline, to avoid one row per crawler) and then logged in via a normal session token.
* `create_guest_user()`: `token = base64url(strong_rand_bytes(16), no pad)` (22 chars); email `"guest-#{token}@guest.marginalia.local"` (validated with `validate_unique: false`, so uniqueness is only enforced by the DB index); password = `base64url(strong_rand_bytes(32), no pad)` (43 chars, hashed with bcrypt); `confirmed_at = now(second)`; `is_guest = true`. Insert.
* Upgrade: `claim_guest_account` (above) edits the same row, so drafts stay owned.
* Web gating: `require_real_account` plug / on_mount redirects guests to `/users/register` with flash "Create an account to keep your drafts."
* **Cleanup: none.** No periodic job, no TTL, no deletion path in `lib/`. A guest row lives until its `ON DELETE CASCADE` owner is removed manually. Session tokens also never expire in the database; they are merely ignored after 14 days.

### 2.7 Notifier and the only email
`UserNotifier.deliver_update_email_instructions(user, url)`: Swoosh email, `to = user.email`, `from = {"Marginalia", "contact@example.com"}`, subject `"Update email instructions"`, **text body only**. Body string, exactly (`\n` = newline):
`"\n==============================\n\nHi #{user.email},\n\nYou can change your email by visiting the URL below:\n\n#{url}\n\nIf you didn't request this change, please ignore this.\n\n==============================\n"`
Returns `{:ok, email}` on `Mailer.deliver` ok. This is the only email the application sends.

### 2.8 Mailer configuration
`Marginalia.Mailer` = `Swoosh.Mailer, otp_app: :marginalia`. `config.exs`: `adapter: Swoosh.Adapters.Local` for **dev and prod** (prod.exs/runtime.exs do not override), `Swoosh.Adapters.Test` in test; `config :swoosh, :api_client, false`. The Local adapter keeps mail in memory; in prod nothing is delivered and there is no mailbox route (dev routes only in dev). So the email-change flow cannot complete in prod unless the adapter is replaced.

---

## 3. `Marginalia.LLM` (the one model client)

Everything that talks to a model goes through here. Library: `Req 0.7.4` (Finch), `Jason`. One HTTP POST per call, non-streaming.

### 3.1 Providers (constants)
| | `deepseek` | `openai` |
|---|---|---|
| label | `"DeepSeek Flash"` | `"Sol 5"` |
| endpoint | `https://api.deepseek.com/chat/completions` | `https://api.openai.com/v1/chat/completions` |
| key config | `:deepseek_api_key` (env `DEEPSEEK_API_KEY`) | `:openai_api_key` (env `OPENAI_API_KEY`) |
| model | `deepseek-flash` | `gpt-5.6-sol` |
| fast_model | `deepseek-flash` | `gpt-5.4-nano` |
| max-tokens field name | `max_tokens` | `max_completion_tokens` |
| default_body | `{"reasoning_effort":"low"}` | `{"reasoning_effort":"low"}` |
| reasoning_headroom | 24000 | 24000 |

Note on DeepSeek model ids: bare `deepseek-flash` turns **reasoning on**; `deepseek-chat` is the same model with thinking off (used by Mutterings).
Provider selection `resolve(x)`: `nil` -> deploy default; string/atom `"openai"|:openai` -> openai, `"deepseek"|:deepseek` -> deepseek; any other value -> deploy default (never errors).
Deploy default `provider_name()`: config `:llm_provider` (env `LLM_PROVIDER`, default `"deepseek"`); `"openai"` or `:openai` -> `:openai`, anything else -> `:deepseek`.
Endpoint override: config `:llm_endpoints` map keyed by the key-config atom (test only sets `http://127.0.0.1:1/...` so tests never leave the machine).
Backoff base: config `:llm_backoff_ms` default 250 (test 0).

### 3.2 `chat(opts)` -> `{:ok, message_map} | {:error, term}`
Options: `:provider`, `:model`, `:messages` (required; list of `%{"role","content"}`), `:tools`, `:tool_choice`, `:temperature`, `:json`, `:max_tokens`, `:effort`, `:timeout`.

1. `prov = resolve(opts[:provider])`. Key = config value for `prov.key`; if not a non-empty binary -> `{:error, :no_api_key}` (no request).
2. Build JSON body, starting from `default_body` and merging/adding in this order (later wins):
   * `"model"` = `opts[:model]` || `config :llm_model` (env `LLM_MODEL`) || `prov.model`.
   * `"messages"`.
   * `"reasoning_effort"` = `to_string(effort)` iff `effort in [:low,:high,:none,"low","high","none"]`; any other/nil value leaves the default `"low"`.
   * `"tools"` iff given. `"tool_choice"` = `opts[:tool_choice]` || (`"auto"` iff tools given).
   * `"temperature"` iff non-nil.
   * `prov.max_tokens_field` = `asked + 24000` iff `:max_tokens` non-nil (the headroom is **added** to what the caller asks, to let reasoning not eat the answer).
   * `"response_format" = {"type":"json_object"}` iff `:json` truthy.
3. `POST` to the endpoint with header `authorization: Bearer <key>` (Req adds `content-type: application/json` and its own defaults: `accept-encoding`, `user-agent: req/0.7.4`). `receive_timeout` = `opts[:timeout]` || **300000 ms**. Req's own retry is not applied to POST (default `:safe_transient` retries only GET/HEAD). Req follows redirects and decodes JSON responses by content-type.
4. Response handling (`attempt` starts at 1, `@max_attempts = 3`):
   * HTTP 200 whose decoded body is a map with `"choices": [choice | _]`: log usage (below), then `interpret(choice)`:
     * `choice["finish_reason"] == "length"` -> `{:error, :truncated}` (**not retried**, even if content present).
     * else if `choice["message"]` present -> `{:ok, message}` (the full message map: `"role"`, `"content"`, possibly `"tool_calls"`, `"reasoning_content"`).
     * else `{:error, {:unexpected, inspect(choice) cut to 200 chars}}`.
   * HTTP status in `[429,500,502,503,504]` -> retriable `{:error, :rate_limited}`.
   * Any other HTTP result (including 200 without usable `choices`, 400, 401, ...) -> `{:error, {:http, status, inspect(body) cut to 300 chars}}` (not retried).
   * Transport error -> retriable `{:error, {:transport, inspect(reason)}}`.
   * Retriable errors: if `attempt >= 3` return the error; else sleep then retry the same body with `attempt+1`. `sleep = trunc(2^attempt * llm_backoff_ms)` => 500 ms after the 1st failure, 1000 ms after the 2nd (default). If `sleep > 0` actually sleep `sleep + uniform(1..400)` ms. (The in-code comment says 0.5 s and 1.5 s; the arithmetic gives 0.5 and 1.0.)
5. Usage reporting after a 200: reads `usage.prompt_cache_hit_tokens`, `prompt_cache_miss_tokens`, `prompt_tokens` (default hit+miss), `completion_tokens`, `completion_tokens_details.reasoning_tokens`; if `prompt > 0` logs info `"marginalia llm: prompt=P cached=H (N%) completion=C reasoning=R"` (N = round(H/P*100)); emits telemetry `[:marginalia,:llm,:usage]` measurements `{prompt, cached, completion, reasoning}` metadata `{provider: label}`.

### 3.3 `json(opts)` -> `{:ok, map} | {:error, ...}`
`chat(opts + json: true)`. Matches `{:ok, %{"content" => content}}`; decodes `content || ""` with Jason; success only if the result is a **map**; otherwise `{:error, :invalid_json}`. Chat errors pass through unchanged. **Quirk:** if the returned message has no `"content"` key at all, the `with` falls through and `json/1` returns `{:ok, message}` undecoded.

### 3.4 `call_tool(opts)` -> `{:ok, arguments_map} | {:error, ...}`
Requires `:tool` (a `%{"type"=>"function","function"=>%{"name",...}}` map). Calls `chat` with `tools: [tool]` and:
* `tool_choice` = `{"type":"function","function":{"name": <tool name>}}` **only when `effort in [:none,"none"]`**; otherwise `"auto"` (DeepSeek rejects a forced choice while thinking is on).
* On `{:ok, %{"tool_calls" => [%{"function"=>%{"arguments"=>args}} | _]}}`: Jason-decode `args || "{}"`; map -> `{:ok, map}`, else `{:error, :invalid_json}`. Only the **first** tool call is read.
* Any `{:ok, message}` without tool_calls -> `{:error, :no_tool_call}`.
* Errors from `chat` pass through.
All `call_tool` callers in this layer use `effort: :high`, hence `tool_choice: "auto"`; a model that answers in prose yields `:no_tool_call`.

### 3.5 Other public functions
* `provider_name/0`, `available/0` = `[:deepseek, :openai]`.
* `choices/0`: for every provider with a configured key: `%{name, label, model}`, sorted by label.
* `reasoning_effort(provider \\ nil)` -> `"low"`; `reasoning_headroom(provider \\ nil)` -> 24000; `token_budget(provider, asked)` -> `nil` if asked nil else `asked + headroom`; `label(provider \\ nil)`.
* `default_model(provider \\ nil)` = env `LLM_MODEL` || provider model. `fast_model(provider \\ nil)` = env `LLM_FAST_MODEL` || provider fast_model.
* `configured?(provider \\ nil)` -> key present. `endpoint(prov)` as above.
* No retry on `:truncated`, `:invalid_json`, `:no_tool_call`, `{:http,...}`; callers decide.

---

## 4. Folders (`folders.ex`)

All functions scope by `user_id`. IDs from forms may be strings; `cast_id`: integer passes, binary must `Integer.parse` fully (`{n, ""}`), else nil. `owned_parent(x, user_id)`: `nil`, `""`, `"root"` -> nil; otherwise the id of the folder iff the user owns it, else **nil** (a forged parent silently becomes root).

| function | behavior |
|---|---|
| `list_folders(user_id)` | all the user's folders ordered by `lower(name)` asc, then `id` asc |
| `get_folder(user_id, id)` | folder owned by user or nil |
| `change_folder(folder \\ %Folder{}, attrs \\ %{})` | `Folder.changeset` |
| `create_folder(user_id, attrs, opts \\ [])` | attrs atom-or-string keys `name`, `parent_id`; parent via `owned_parent`; insert `%Folder{user_id}` with `Folder.changeset(%{name, parent_id})`, passing `opts` to `Repo.insert` (`mode: :savepoint` used by backfill). `{:ok, folder}` / `{:error, changeset}` |
| `rename_folder(user_id, id, name)` | `{:error, :not_found}` or update via changeset (trim, <=80, unique) |
| `delete_folder(user_id, id)` | transaction: `works.folder_id := folder.parent_id` for its works; child folders `parent_id := folder.parent_id`; `Repo.delete!(folder)`. Returns `{:ok, deleted}` / `{:error, :not_found}`. (If a lifted child collides by name with a sibling in the new parent the unique index raises and the transaction aborts with an exception.) |
| `move_folder(user_id, id, parent_id)` | not owned -> `{:error, :not_found}`; `parent = owned_parent(parent_id)`; `parent == folder.id` or `descendant?(user, parent, folder.id)` -> `{:error, :cycle}`; else set `parent_id` and re-run `Folder.changeset(%{name: folder.name})` (so a name clash gives a changeset error) -> update |
| `move_work(user_id, work_id, folder_id)` | `Works.get_work(user_id, work_id)` nil -> `{:error, :not_found}`; else set `work.folder_id = owned_parent(folder_id, user_id)` (nil unfiles; foreign folder id unfiles too) |
| `tree(user_id)` | `%{folders: [node], works: [work]}`; node = `%{folder, count, folders, works}`; children by `parent_id` in `list_folders` order; works come from `Works.list_works` (**newest id first**) grouped by `folder_id`; `count` = works in the node + sum of children's `count` |
| `unfiled_collection_count(user_id)` | count works with non-nil `collection` and nil `folder_id` |
| `backfill_from_collections(user_id, parent_name \\ "Cases")` | loose = user's works with collection non-nil and folder nil; none -> `{:ok, 0}`. Else in one transaction: parent = `get_or_create(parent_name, nil)` (nil parent_name -> no parent); for each collection group: folder = `get_or_create(collection, parent.id)`; update those works' `folder_id`; sum counts. Returns `{:ok, filed}`. Idempotent; never moves already-filed works |
| `get_or_create(user, name, parent_id)` (private) | try `create_folder(..., mode: :savepoint)`; on any changeset error `Repo.one!` the sibling with that exact name and same parent (nil parent = root) |
| `descendant?(user_id, id, ancestor_id)` | `nil` id -> false; walk `parent_id` chain upward (owned folders only); true if any parent equals `ancestor_id` |
| `publish(user_id, id)` | owner check first: `Accounts.owner()` nil or `owner.id != user_id` -> `{:error, :not_owner}`; folder not found -> `{:error, :not_found}`; else set `published_at = now (second)` and `slug = folder.slug || mint_slug(folder.name)` (existing slug is kept even after rename) |
| `unpublish(user_id, id)` | `published_at := nil`, slug kept |
| `get_published(slug)` | folder with that slug and non-nil `published_at`, any owner; non-binary -> nil |
| `published()` | all folders with `published_at` set, `published_at` desc |

**`mint_slug(name)`**: `base = lower(name) |> replace(~r/[^a-z0-9]+/u, "-") |> trim("-") |> first 60 chars`; empty -> `"stack"`. If any folder (any user) already has `slug == base`, return `base <> "-" <> base64url(strong_rand_bytes(3), no padding)` (4 chars). (Race is closed only by the unique index.)
Examples: `"A backend"` -> `"a-backend"`; `"owner/repo"` -> `"owner-repo"`; `"!!!"` -> `"stack"`.

---

## 5. Links

### 5.1 `Marginalia.Links` (`links.ex`)
Constant `@max_edges = 140`.

| function | behavior |
|---|---|
| `get_or_create(a, b)` | `a == b` -> `{:error, :same_work}`. Canonicalise `{min, max}`. Existing row -> `{:ok, link}`. Else invalidate cache keys `:public_links` and `:published_cases`, then insert `%Link{}` via `Link.changeset(%{a_work_id, b_work_id})` (status default `"pending"`). Note: the insert result is returned directly (so a failure is `{:error, changeset}`) |
| `get(id)`, `get_for(a, b)` | by id; by canonical pair |
| `linkable(user_id, work_id)` | user's works, status `"read"`, id != work_id, `inserted_at` desc. `linkable(user_id)`: same without the exclusion |
| `for_user(user_id)` | links where either work belongs to user; preloads `a_work`,`b_work`; `updated_at` desc |
| `for_work(work_id)` | links touching the work; `updated_at` desc, `id` desc; preloads both works |
| `other(link, work_id)` | `link.b_work` if `link.a_work_id == work_id` else `link.a_work` (needs preloads) |
| `works(link)` | `{a_work, b_work}` preloaded |
| `set_status(link, status, attrs \\ %{})` | `Link.changeset(link, Map.merge(attrs, %{status: status}))` update (attrs use atom keys e.g. `summary:`, `error:`) |
| `edges(link_id)` | edges of a link ordered `ordinal` asc, `id` asc, preloading `from`,`to` nodes |
| `edges(%Link{})` | same, but each `rationale` passed through `plain(rationale, link)` |
| `clear_edges(link)` | invalidate the two cache keys; delete all edges of the link |
| `edge_count(link_id)` | count |
| `store_edges(link, proposed, types, max \\ 140)` | see below |
| `passage(node)` | if node has non-empty `quote` and `section_id`: load section; split `section.body` with `Reading.split/1` (blank-line paragraphs, fenced code kept whole); first paragraph containing the quote, else the quote. With a quote but no section: the quote. Else the node `title` |
| `stats(link)` | `%{edges: n, by_type: frequencies of edge_type, a_nodes: distinct node ids on side A across both ends, b_nodes: same for B}` |
| `notes_for(link, work_id)` | margin notes for one side (below) |
| `margin(link, lead_id)` | `notes_for` plus far-end info (below) |
| `reading(link, lead_id)` | `%{lead, other, page: Reading.page(lead, notes: margin(link, lead_id))}` |
| `pages(link)` | `{page_a, page_b}` from `Reading.page` with `notes_for` each, then each note gets `peer_ref` = block ref of the paragraph that holds the peer node on the other page |
| `summary(link)` | `nil` if summary nil else `plain(summary, link)` |
| `plain(text, link)` | substitution below |
| `clusters(user_id)` | components below |
| `public_links()` | cached 5 min under `:public_links`; below |
| `public_link(id)` | below |

**`store_edges(link, proposed, types, max)`**
1. Invalidate caches `:public_links`, `:published_cases`.
2. `allowed` = map `node_id -> work_id` for all nodes whose `work_id` is the link's A or B.
3. Keep only `proposed` items that are maps (others vanish and are NOT counted as dropped). For each, `normalise` (rules in order, first failing -> `nil` -> counted as dropped):
   * `from = int(raw["from"])`, `to = int(raw["to"])` where `int` accepts integers or strings via `Integer.parse` (prefix parse, `"12abc"` -> 12; failure -> nil); `type = raw["type"]`; `why = trim(to_string(raw["why"]))`.
   * `from_side = allowed[from]`, `to_side = allowed[to]`; either nil (invented id, or node of a third work) -> drop.
   * `from_side == to_side` (both in one document) -> drop.
   * `type not in types` -> drop.
   * `why == ""` -> drop.
   * else row `%{from_id, to_id, edge_type: type, rationale: why}`.
4. `uniq_by {from_id, to_id, edge_type}` (first wins), `take(max)`, assign `ordinal = 0,1,2,...`.
5. Insert each with `LinkEdge.changeset(row + link_id)`; `kept` = number of successful inserts (a unique-index failure is silently not counted).
6. Return `{kept, dropped}` where `dropped` counts only normalisation rejections (not dedupe, not the `max` cut).

**`notes_for(link, work_id)`**: for each edge (with plain rationale), `{near, far}` = `{from, to}` if `from.work_id == work_id` else `{to, from}`. Emit a note only if `near.work_id == work_id`, `near.section_id` is set, and `near.quote` is non-empty:
`%{id: {:link, edge.id, near.id}, key: "link:#{edge.id}", section_id: near.section_id, kind: edge.edge_type, quote: near.quote, title: (if edge.from_id == near.id then "→ " else "← ") <> far.title, body: edge.rationale (plain), stale: false, edge_id: edge.id, peer: far.id}`.
**`margin`**: those notes, plus `far_title, far_body, far_quote, far_kind (node_type), far_section` (the far node's section **ordinal**, looked up from the other work's sections).

**`plain(text, link)`** (the A/B -> titles substitution). `name(work)` = the part of `work.title` after the first `" — "` if present, else the whole title. One left-to-right `Regex.replace` over
`~r/(\A|\bManuscripts?\s+|[.;:—-]\s+|\s+)([AB])(['’]s)?(?![\p{L}\p{N}'’])/u` with a **function** replacement (so titles starting with digits cannot be read as backreferences and replaced text is never rescanned). For each match `(whole, pre, letter, poss)`:
1. if `pre` matches `~r/\bManuscripts?\s+\z/` -> result `name(letter) <> poss` (the word "Manuscript" and its space are dropped);
2. elif `poss != ""` -> `pre <> name(letter) <> poss`;
3. elif `pre == ""` or `pre` matches `~r/[.;:—-]\s+\z/` -> `pre <> name(letter)`;
4. else (bare letter after plain whitespace) -> unchanged `pre <> letter <> poss`.
`plain(nil, _)` -> nil. `A` -> `name(a_work)`, `B` -> `name(b_work)`.
Examples (titles `"1. A page with no script on it"` and `"2. The backend scaffold"`):
`"B answers A's open question."` -> `"2. The backend scaffold answers 1. A page with no script on it's open question."`; `"Manuscript B extends Manuscript A."` -> `"2. The backend scaffold extends 1. A page with no script on it."`; `"See Part A and Exhibit B."` unchanged; `"It extends B."` unchanged.

**`clusters(user_id)`**: `links = for_user`; works = distinct works across links. Components by union-find over `(a_work_id, b_work_id)` (the parent map is built from the links, union sets `parent[root(a)] = root(b)`). For each component (set of work ids): `inside` = links whose `a_work_id` is in the set; `members` = works sorted by `title`; `linked` = set of `{a_work_id, b_work_id}`; `missing` = all `{a, b}` pairs of members with `a.id < b.id` not in `linked`. Result list of `%{works, links, missing}` sorted by `-length(works)`.

**`public_links()`**: owner = `Accounts.owner()`; nil -> `[]`. Else for each link in `for_user(owner.id)`: `%{link, edges: total edge count, tensions: count of edge_type == "tension"}` (two grouped queries), keep those with `edges > 0`, sort by `{-tensions, -edges}`. **`public_link(id)`**: owner exists, link exists, **both** works' `user_id == owner.id`, and `edge_count > 0`; returns the link with works preloaded or nil.

### 5.2 `Links.Bulk` (`links/bulk.ex`): choosing which pairs of a folder to relate
Constants `@concurrency 3`, `@max_pairs 24`, `@line_cap 220`.

* `describe(work)`: first non-blank of: (1) `capability` of the **highest-id** `stack_steps` row for the work, (2) the first two non-null section summaries (ordered by ordinal) joined by `" "`, (3) `work.first_impression`; else `""`. Then whitespace runs collapsed to one space, trimmed, first 220 chars.
* `sheet(user_id, folder_id)`: user's works in that folder, sorted by `id` asc, `n` from 1 -> `%{n, work, line: describe(work)}`.
* `propose(sheet, opts)`: listing = lines `"#{n}. #{title}"` + (`" — #{line}"` if line non-empty) joined by `"\n"`. One `LLM.call_tool` (call #1 in section 13) with user message `"#{length(sheet)} documents:\n\n#{listing}"`. On success `{:ok, validate(raw, sheet)}`; else `{:error, reason}`.
* `validate(raw, sheet)` -> `%{pairs, dropped, skipped}`. For each `raw["pairs"]` element that is a map, in order, with `a = as_int(p["a"])`, `b = as_int(p["b"])` (`as_int`: int passes; string -> trim then `Integer.parse` prefix; else nil), unordered key `{a,b}`:
  * `a` or `b` nil -> dropped message `"a pair without two numbers: #{inspect(%{"a"=>..,"b"=>..})}"` (only keys present are shown).
  * `a == b` -> `"#{a} paired with itself"`.
  * either not a sheet number -> `"#{inspect(missing_list)} is not in this folder"` (missing = those of `[a, b]` absent, e.g. `[140]`).
  * unordered pair already kept -> `"#{a}–#{b} proposed twice"` (en dash U+2013).
  * else keep `%{a: work_a, b: work_b, why: trim(p["why"]), expect: trim(p["expect"])}` (non-strings become `""`).
  Final `pairs` = first 24 kept; `skipped = trim(raw["skipped"])`.
* `run(user_id, folder_id, opts)`: folder not owned -> `{:error, :no_folder}`; sheet empty -> `{:error, :empty_folder}`; calls `opts[:on_stage].("choosing the pairs")` if given; `propose`; on error `{:error, reason}`. If `opts[:propose_only]` -> `{:ok, triage + started: []}` else `{:ok, Map.merge(triage, relate(pairs, opts))}`.
* `relate_pairs(pairs, opts)` = `relate`. `relate`: split pairs into eligible (both works `status == "read"`) and ineligible. Eligible run through `Task.async_stream` (`max_concurrency 3`, `timeout 300000`, `on_timeout :kill_task`): `Links.get_or_create(a.id, b.id)` -> on ok `Analysis.Linker.run(link, opts[:provider])` (**its result is ignored**) and the pair map gets `link_id`; on error the pair gets `error`; then `opts[:on_pair].(pair, total_eligible)` is called from inside the task. Results of crashed/timed-out tasks (`{:exit,_}`) are dropped. Returns `%{started: [pair maps], not_read: ineligible(ineligible_pairs)}`.
* `ineligible(pairs)`: for each pair with an unread side: `"#{a.title} ↔ #{b.title}: #{unread titles joined by " and "} has not been read"`.

### 5.3 `Links.Chat` (`links/chat.ex`)
No tools, no storage ("it is not kept": history lives in the LiveView).
`ask(link, history, opts)`: messages = `[system SYSTEM, system card(link)] ++ history ++ [cited_card if any]`; `LLM.chat(provider: opts[:provider], model: LLM.default_model(provider), effort: :low, temperature: 0.5, max_tokens: 4000, messages)`. Returns `{:ok, text}` iff `message["content"]` is a non-empty binary; `{:ok, _}` otherwise -> `{:error, :empty_reply}`; errors pass through. `history` items are `%{"role","content"}` maps oldest first. `prompt/0` returns the system text; `passes/0` returns metadata `[%{id: "link_chat", name: "Talking about a pair", model: default_model, runs: "per message, on a linked pair", produces: "answers about how two drafts relate", prompt}]`.

**`card(link)`** (exact layout; `{a,b}` = link works; edges = `Links.edges(link)` i.e. plain rationale):
```
# THE PAIR

A: #{a.title} — #{a.word_count} words
B: #{b.title} — #{b.word_count} words

#{if link.summary: "How they relate, as already established:\n#{link.summary}\n" else ""}
# THE EDGES BETWEEN THEM (#{n_edges})

#{edge lines joined by "\n"}

# MAP OF A: #{a.title}
#{map(a)}

# MAP OF B: #{b.title}
#{map(b)}
```
(trailing newline.) Note `link.summary` here is the raw stored summary (not `plain`). `edge_line(e, a_id)` = `"- #{A|B}:[#{e.from_id}] #{e.from.title} --#{e.edge_type}--> #{A|B}:[#{e.to_id}] #{e.to.title}\n    #{e.rationale}"` where side is `"A"` if `node.work_id == a.id` else `"B"`.
`map(work)`: sections `id -> ordinal`; nodes of the work (`Works.list_nodes`, order ordinal asc, id asc) grouped by `node_type` (map order, i.e. Elixir map iteration = ascending key order of the type strings); each group `"\n## #{type}\n" <> lines joined "\n"` and groups joined by `"\n"`. `node_line` = `"- [#{id}]" <> (" (§#{section_ordinal})" if node.section_id) <> " #{title}" <> ("\n    \"#{one_line(quote)}\"" if quote non-empty)`; `one_line(q)` = whitespace runs (unicode) to single space, then first 160 chars.
**`cited_card(link, edge_ids)`**: nil or `[]` -> nil. Otherwise the edges of the link whose id is in `edge_ids`; none -> nil; else one system message:
`"The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely.\n\n"` + blocks joined `"\n\n"`, each:
```
## #{UPPERCASE(edge_type with _ replaced by space)}
Why it was drawn: #{e.rationale}

### #{A|B} — #{e.from.title}
#{Links.passage(e.from)}

### #{A|B} — #{e.to.title}
#{Links.passage(e.to)}
```
(each block ends with a newline).

### 5.4 Linker (outside scope, contract only)
`Analysis.Linker.run(link, provider)`: sets link status `linking` (error nil), broadcasts `{:link,:start}` on PubSub `"link:#{link.id}"`; fails with `:not_read` if either work has no nodes; else `LLM.json` (effort high, temperature 0.4, max_tokens 24000; one retry with an extra suffix when the first answer is `:truncated`), `Links.clear_edges`, `Links.store_edges(link, edges, ~w(develops pays_off requires tension answers echoes))`, status `linked` with `summary`. Failure sets status `failed`, `error: inspect(reason)`. `Linker.start(link, provider)` runs it under `Marginalia.TaskSupervisor` (fire and forget). Its prompt lives in `analysis/linker.ex` and is not part of this document.

---

## 6. Cuts (`cuts.ex`): reading a folder

A "cut" is one reading per folder (unique per `(user, folder)`), built from member texts, validated by quote-location.

### 6.1 `Cuts.locate(needle, haystack)` (pure; used by Stacks too)
Both binaries else nil.
1. `trim(needle) == ""` -> nil.
2. `haystack` contains `needle` byte-exactly -> return `needle` unchanged.
3. Else loose: `flat_needle = collapse(needle)` (regex `\s+` -> one space, then trim; if empty -> nil). Build `flat_hay` from the haystack **bytes**: iterate bytes; for a whitespace byte (`space, \n, \t, \r`): skip it if still at the very start of output or the previous byte was whitespace; otherwise emit one `" "` and remember the offset of the **first** whitespace byte of the run; non-whitespace bytes are copied with their own offsets. Find `flat_needle` in `flat_hay` (byte substring, case-sensitive, first occurrence). Return the original haystack bytes from `offset[at]` through `offset[at+len-1]` inclusive. Thus the returned text is the haystack's own wording (including its original line breaks), and every token must be present in order.
Examples (haystack `"A Blimp closure can see its caller's locals. `eval.zig` has a test\nthat says so outright, and tail call elimination is written around it."`): `"A Blimp closure"` -> same; `"has a test that says so outright"` -> `"has a test\nthat says so outright"`; `"A Blimp closure cannot see anything"` -> nil; reordered words -> nil; `"   \n "` -> nil.
(Port in terms of characters is fine if offsets are kept consistent; the Elixir works on bytes. `\s` in the needle collapse is PCRE ASCII `\s`, which also includes `\v` and `\f`, but the haystack side only collapses space, `\n`, `\t`, `\r`.)

### 6.2 Members
`members(user_id, folder_id)`: find the folder's node in `Folders.tree(user_id)` (recursive search by `folder.id`). Not found -> `[]`. If the node has child folders: **child members** (works in the folder are ignored); else **work members**.
* Child members: for each child folder in tree order, `n` from 1: `%{n, kind: "folder", id, label: folder.name, read?: cut != nil and cut.status == "read", text}` where `cut = get_folder_cut(user, child.id)`; `text` = if cut is read: `trim("#{thesis}\n\n#{threads as "- <claim>" lines joined "\n"}")`, else `"(not read yet) holds: " <> titles` where titles = child's work titles ++ child folder names joined `", "`.
* Work members: the node's works sorted by `id` asc, `n` from 1: `%{n, kind: "work", id, label: title, read?: work.status == "read", text: work_text}`; `work_text` = `trim("#{first_impression || ""}\n\n#{body}")` where `body` = if the work has nodes: `"<node_type>: <title>" + ("\n> " <> quote if non-empty)` per node (`Works.list_nodes` order) joined `"\n\n"`; if no nodes: each section's body truncated to its first 1200 chars, joined `"\n\n"`.
* `content_sha(members)` = lowercase hex SHA-256 of `members |> map("#{kind}:#{id}:#{text}") |> join("\n")`.
* `current?(cut, user_id)` = `cut.folder_id && cut.content_sha == content_sha(members(user_id, cut.folder_id))` (nil if no folder). `current?/1` exists only for a cut with nil sha and returns false.

### 6.3 CRUD and state machine
* `list_cuts(user_id)` updated desc, preload folder. `get_cut(user_id, id)`. `get_folder_cut(user_id, folder_id)`. `delete_cut(cut)`. `set_status(cut, status, detail \\ nil)`: `status`, `status_detail := detail` (no validation).
* `open_folder_reading(user_id, folder_id, question \\ nil)`: folder not owned -> `{:error, :not_found}`. attrs `{title: folder.name, folder_id, scope: "folder", status: "draft"}` plus `question` only if non-nil. Existing cut for the folder -> update through `Cut.changeset` (**thesis/threads/etc. are kept**, status reset to `draft`, question unchanged if none given); else insert `%Cut{user_id}`.
* Status machine: `draft` -> (page calls `set_status(cut,"reading")` and starts the read) `reading` -> `read` (result stored with status "read") or `failed` (`status_detail` = `inspect(reason)` or `"this folder holds nothing to read"`). `status_detail` is not cleared on success. **A restart mid-read leaves `reading` forever: `Recovery` does not sweep cuts** (see S5).

### 6.4 `read(cut, user_id)` (synchronous; the web page runs it in `start_async` tied to the socket, not in `Runs`)
`members = members(user_id, cut.folder_id)`. Empty -> `set_status(cut, "failed", "this folder holds nothing to read")`. Else LLM call #4 (`LLM.json`, section 13). On `{:ok, raw}`: `{result, dropped} = validate(raw, members)`; `Cut.result_changeset` with `result + dropped + content_sha(members) + status "read" + members: members mapped to Map.take(:n,:kind,:id,:label,:read?)` and update. On `{:error, reason}`: `set_status(cut, "failed", inspect(reason))`.

User message (`prompt/2`), exact:
```
#{if question non-blank: "The reader asks: #{question}\n\n"}Group: #{cut.title}
Its members are #{kind}.

#{members each: "### Member #{n}: #{label}\n\n#{text}\n" joined by "\n"}
---

Report:

- `thesis`: one or two sentences. What these members, together, establish.
  If they establish nothing together, say that.
- `threads`: things true across two or more members that no single one
  states. Each: `claim` (one sentence) and `evidence` — two or more entries,
  each `{"member": N, "quote": "..."}` quoted from that member.
- `tensions`: places the members disagree, or where one revises another.
  Same shape. `[]` if there are none.
- `not_supported`: one sentence naming something a reader might expect this
  group to show but which these members do not support. `""` if none.

Shape:

{"thesis": "...",
 "threads": [{"claim": "...", "evidence": [{"member": 1, "quote": "..."}]}],
 "tensions": [],
 "not_supported": "..."}
```
`kind` = `"sub-groups"` if every member has `kind == "folder"` else `"documents"`. (The heredoc's body ends with a newline.) Indentation shown is relative: the `Report:` bullets, continuation lines (two spaces) and the JSON shape's second-to-fourth lines (one space) are exactly as shown.

### 6.5 `validate(raw, members)` -> `{%{thesis, threads, tensions, not_supported}, dropped}`
`text(v)` = trimmed binary else `""`. `by_n` = members by `n`. `check_group(items, label)` for `raw["threads"]` (label `"thread"`) then `raw["tensions"]` (label `"tension"`); `dropped = threads_drops ++ tensions_drops`. If `items` is not a list -> `{[], []}` (no message).
Per item (assumed a map): `claim = text(item["claim"])`; empty -> drop `"#{label}: no claim"`. Else evidence check: `item["evidence"]` not a list -> `{[], ["#{label} #{short(claim)}: no evidence"]}`. For each `ev`: `n = as_int(ev["member"] || ev["document"])` (older key accepted), `quoted = text(ev["quote"])`, `member = by_n[n]`:
  * no member -> drop `"#{label} #{short(claim)}: member #{inspect(ev["member"])} is not in this group"`;
  * `found = quoted != "" and locate(quoted, member.text)`: truthy -> keep `%{"member"=>n,"kind"=>member.kind,"id"=>member.id,"label"=>member.label,"quote"=>found}` (stored quote is the member's own wording);
  * else drop `"#{label} #{short(claim)}: quote is not in member #{n}"`.
  If `>= 2` evidence kept: keep `%{"claim"=>claim, "evidence"=>kept}` and append the evidence drops. Else drop item and append evidence drops plus `"#{label} #{short(claim)}: #{k} verifiable citation(s), needs 2"`.
`short(s)` = `inspect(first 40 chars of s)` (so it is wrapped in double quotes with escapes). `as_int`: int, or string via prefix `Integer.parse`, else nil. `thesis` and `not_supported` = `text(...)`.

---

## 7. Stacks (`stacks.ex`, `stacks/step.ex`, `stacks/story.ex`)

A **stack** = a folder whose works are an ordered series. Passes, all driven by buttons on the stack page and run under `Runs` (section 11): forward read, deepen, compose, plus summarise-all, read-each, relate (Links.Bulk). `@body_cap = 14_000`.

### 7.1 Ordering and text
* `order(works)`: `leading_number(work)` = `Integer` of `^\s*(\d+)\s*[.):-]` on the title, else nil. If **every** work has one and the numbers are **distinct**, sort by that number; else sort by `id` asc. (`"10. Tenth"` sorts after `"9. Ninth"`.)
* `documents(user_id, folder_id)`: works of the user in that folder (subfolders ignored), then `order`.
* `list_steps(folder_id)`: steps by `ordinal` asc, preload work. `get_step(folder_id, ordinal)`. `get_story(folder_id)`.
* `text_of(work)`: section bodies (in `Works.list_sections` order) joined `"\n\n"`, then first **14000 characters**. `fingerprint(work)` = lowercase hex SHA-256 of `text_of`. `current?(step, work)` = `step.fingerprint == fingerprint(work)`.
* `story_fingerprint(steps)` = hex SHA-256 of lines `"#{ordinal}|#{capability}|#{lesson}|#{mechanism}|#{pitfall}|#{revised_by}"` (nil -> empty) joined `"\n"`. `story_current?(story, folder_id)` compares to the current steps.

### 7.2 Forward read: `read_step(user_id, folder_id, work, ordinal, prior, opts)` and `read_stack(user_id, folder_id, opts)`
`read_stack`: `docs = documents(...)`, `building = opts[:building] || folder.name`. Sequentially, `i` from 1 over docs: `read_step(user, folder, work, i, prior_steps_in_order, building: building)`. `{:ok, step}` -> `opts[:on_step].(step, i, length(docs))` and the step joins `prior`; `{:error, r}` -> appended to errors as `{i, work.title, r}` (and the ordinal `i` is skipped in `prior`). Returns `{steps, errors}`.
`read_step`: LLM call #5 (tool `report_step`, section 13) with user message:
```
#{building}# Document #{ordinal}: #{work.title}

What the earlier documents established, in order:
#{established}

## The document

#{text_of(work)}
```
where `building` = `"The series builds: #{b}\n\n"` iff `opts[:building]` is a non-empty binary, and `established` = `"  (nothing — this is the first document)"` for no prior steps, else the **last 25** prior steps as `"  #{ordinal}. #{capability}"` joined `"\n"`. (Ends with a newline.)
On `{:ok, raw}`: `{attrs, dropped} = validate(raw, body, ordinal)`; upsert a `%Step{}` via `Step.changeset(attrs + folder_id, work_id, ordinal, fingerprint, dropped)` with `on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: [:folder_id, :work_id]` — i.e. a re-read **overwrites every column**, resetting `mechanism, watch_for, revised_by, revision, revision_quote, deep_dropped, deepened_at` to their defaults. On error returns `{:error, reason}`.

**`validate(raw, body, ordinal)`** -> `{attrs, dropped}` (`dropped` is a list of strings, in this order):
1. `requires`: each element of `raw["requires"] || []`, `as_int`: integer `n` with `1 <= n < ordinal` kept; other integers -> `"requires #{n}: not an earlier document"`; non-integers -> `"requires #{inspect(r)}: not a number"`. Final `requires = sort(uniq(kept))`.
2. `pitfall = trim(raw["pitfall"])`; `capability` and `lesson` = `trim(...)` then `scrub(text, "capability"|"lesson")` (leak cut, see 7.6); any leak messages (capability first) are appended **after** the requires messages.
3. `quote = trim(raw["pitfall_quote"])`; `found = (quote != "") ? Cuts.locate(quote, body) : nil`.
   * `pitfall == ""` -> pitfall nil, no message; `found` truthy -> keep pitfall; else pitfall nil and message `"pitfall: quote is not in the document"`.
   * `pitfall_quote` stored = `found` (so it can be set even when the pitfall text was empty/dropped; nil when not located).
4. `excerpts`: for each element `e` of `raw["excerpts"] || []`: `q = trim(e["quote"])` if `e` is a map else `""`. `q == ""` -> `"excerpt: no quote"`. `passage_around(body, q)` nil -> `"excerpt: #{inspect(first 50 chars of q)} is not in the document"`. Else keep `%{"caption" => trim(e["caption"]), "text" => passage}`. Final: first **2**.
   `passage_around(body, quote)`: `found = Cuts.locate(quote, body)`; nil -> nil; else the first block of `Reading.split(body)` that contains `found`, else `found` itself.
Result attrs: `capability, requires, lesson, pitfall, pitfall_quote, excerpts`.

### 7.3 Deepen: `deepen_step(step, chain, opts)` and `deepen_stack(folder_id, opts)`
`deepen_stack`: `chain = list_steps(folder_id)`; `todo = chain` if `opts[:force]` else steps with `deepened_at == nil`. Sequential (deliberately, for the provider's prefix cache). Each `deepen_step(step, chain, opts)`; `{:ok, updated}` -> `opts[:on_step].(updated, length(done)+1, length(chain))`; `{:error, r}` -> errors `{step.ordinal, r}`. Returns `{done_steps, errors}`.
`deepen_step`: loads work; `later = chain steps with ordinal > step.ordinal`; LLM call #6 (tool `deepen_step`) with user message:
```
#{building}# The whole series (>> marks the step you are re-reading)

#{chain lines joined "\n"}

# Step #{step.ordinal}: #{work.title}

What the first reading said it establishes: #{step.capability}
What it said to do: #{step.lesson}
#{"The pitfall it named: " <> pitfall <> "\n" if pitfall (else empty line)}
## The document itself

#{text_of(work)}

## Everything that comes after it

#{later_detail or "(nothing — this is the last step)"}
```
chain line = `">> "` (current step) or `"   "` followed by `"#{ordinal}. #{capability}"`. `later_detail` = for each later step `"### Step #{ordinal}: #{capability}\n#{lesson}"` plus `"\nPitfall: #{pitfall}"` if pitfall present, joined `"\n\n"`. `building` here = `"The series builds: #{b}\n\n"` iff `opts[:building]` is **any** binary (even empty).
Success: `validate_deep(raw, later)` then `Step.deep_changeset(attrs + deep_dropped: dropped, deepened_at: now(second))` update. Failure: update the step with `deep_dropped: ["the second pass failed: #{inspect(reason)}"]`, `deepened_at: nil` and return `{:error, reason}`.

**`validate_deep(raw, later)`** -> `{%{mechanism, watch_for, revised_by, revision, revision_quote}, dropped}`:
* `n = as_int(raw["revised_by"])`, `revision`, `quote` trimmed; `target = later step with ordinal n` (if n non-nil); `haystack = join("\n", [target.capability, target.lesson, target.pitfall || ""])` or `""`; `found = (quote != "" and haystack != "") ? Cuts.locate(quote, haystack) : nil`.
* cond in order: `n` nil or `n == 0` or `revision == ""` -> all three nil, no message; target nil -> nil, `"revision: step #{n} is not a later step"`; `found` nil -> nil, `"revision: quote is not in step #{n}'s summary"`; else `{n, revision, found}`.
* `mechanism = trim(raw["mechanism"])`; empty -> nil with message `"mechanism: empty"` (appended after revision messages). `watch_for` = trim, `""` -> nil.

### 7.4 Compose the longform story: `compose(folder_id, opts)`
`steps = list_steps`; empty -> `{:error, :not_read}`. Calls `opts[:on_stage].("outlining", 0, nil)` (arity 3). Then:
1. **Outline** (LLM call #7, tool `outline_story`). Failure -> returned as `{:error, reason}` (nothing stored). User message:
```
What is being built: #{opts[:building] || "the thing this series builds"}
#{length(steps)} steps, in order. Divide them into parts.

#{spine}
```
`spine` = per step `"#{ordinal}. #{capability}"` plus `"   [#{marks}]"` where marks are (in order) `"pitfall"` if `pitfall` truthy and `"revised by #{revised_by}"` if set, joined `", "`; lines joined `"\n"`.
2. For each part `part` of `outline["parts"] || []`, sequentially, with `i` from 1: `on_stage.("writing", i-1, nparts)`, then **write_part** (LLM call #8, tool `write_part`): `ordinals = (part["steps"] || []) |> as_int each |> drop nils` (duplicates kept); `mine` = steps whose ordinal is in `ordinals` (step order). User message:
```
What is being built: #{opts[:building] || "the thing this series builds"}
The telling is called: #{outline["title"]}

You are writing one part of it: **#{part["heading"]}**
It covers steps #{Enum.join(ordinals, ", ")} and nothing else.

#{detail}
```
`detail` = for each step in `mine`, lines joined `"\n"` then steps joined `"\n\n"`: `"## Step #{ordinal}: #{capability}"`; `"Stands on: #{requires joined ", "}"` if `requires != []`; `"What to do: #{lesson}"`; `"How it works: #{mechanism}"` if set; `"The obvious version is wrong: #{pitfall}"` if set; `"Get right now: #{watch_for}"` if set; `"Walked back by step #{revised_by}: #{revision}"` if revised_by set.
Result map `%{"heading"=>part["heading"], "steps"=>ordinals, "prose"=>prose, "turn"=>w["turn"]}`; if the call fails or lacks `"prose"`: `prose ""`, `turn ""` (the validator later drops it and names the steps). Errors on individual parts are swallowed.
3. After the loop `on_stage.("writing", nparts, nparts)`. Then `store_story(folder_id, steps, outline + "movements" => movements)`.
`store_story`: `{attrs, dropped, uncovered} = validate_story(raw, steps)`; upsert `%Story{}` via `Story.changeset(attrs + folder_id, dropped, uncovered, fingerprint: story_fingerprint(steps))` with `on_conflict: {:replace_all_except,[:id,:inserted_at]}, conflict_target: :folder_id`. Returns `{:ok, story}` (the web run turns that into `:ok`).

**`validate_story(raw, steps)`** -> `{%{title, opening, movements, closing}, dropped, uncovered}`. `ordinals` = set of step ordinals; `seen = {}`; for each `m` in `raw["movements"] || []` in order:
* `heading = trim(m["heading"])`, `prose = scrub(trim(m["prose"]), "part #{inspect(heading)}")` (leak message appended if cut) — non-maps give `""`.
* for each `n` in `m["steps"]` (wrapped in a list): non-integer -> `"part #{inspect(heading)}: #{inspect(n)} is not a step number"`; not in `ordinals` -> `"part #{inspect(heading)}: step #{i} is not in this stack"`; already in `seen` (from earlier **kept** parts) -> `"part #{inspect(heading)}: step #{i} is told twice"`; else accepted into `mine` (a step repeated within the same part is accepted twice).
* `heading == ""` or `prose == ""` -> part dropped with `"a part with no heading"` (if heading empty) or `"a part with no prose"`; its steps are NOT added to `seen`.
* else keep `%{"heading","prose","steps"=>mine,"turn"=>trim(m["turn"])}` and add `mine` to `seen`.
After the loop: `uncovered = sort(ordinals - seen)`; if non-empty append `"#{count} step(s) appear in no part: #{joined ", "}"`. `movements` sorted by first step (`9999` if empty). `opening`/`closing` = `scrub(trim(..), "opening"|"closing")` (messages appended opening then closing). `title = trim(raw["title"])`.

### 7.5 Guide, stats, drafts
* `guide(folder_id)`: for each step: `%{step, requires: steps referenced by step.requires (missing dropped), required_by: steps whose requires contains this ordinal sorted by ordinal, previous: step ordinal-1, next: ordinal+1}`.
* `steps_by_work(user_id)`: `%{work_id => {folder_id, ordinal}}` for the user's steps.
* `read_documents(user_id, folder_id, opts)`: `docs = documents`; `todo = docs` if `:force` else those with `status != "read"`; sequentially for `i, work` run `{:ok, done} = Analysis.run(work, opts[:provider])` (assumed always ok), call `on_step.(work, i, total)`, and if `Works.list_nodes(done.id) == []` add `{work.title, :nothing_read}` to errors. Returns `{total - length(errors), errors}`.
* `summarise_documents(user_id, folder_id, opts)`: `todo = docs` if `:force` else docs with `Document.get(id) == nil`; sequentially `Document.run(work, opts)`; errors `{title, reason}`; `on_step` after each; returns `{total - length(errors), errors}`.
* `stats(user_id, folder_id)` -> `%{documents, read: #steps, stale: docs having a step whose fingerprint differs, pitfalls: steps with non-empty pitfall, excerpts: sum, links: sum of requires lengths, dropped: sum of dropped lengths, summarised: count of document_summaries for the docs with non-empty summary, mapped: docs with status "read", related: count of links with both works in the folder, deepened: steps with deepened_at, deep_failed: steps with nil deepened_at and any deep_dropped starting "the second pass failed", revisions: steps with revised_by, deep_dropped: sum}`.
* `to_draft(user_id, folder_id)`: no story -> `{:error, :not_composed}`; else `Works.create_work(user, %{"title" => story.title || "A reading", "intent" => intent, "body" => body})` (NOT filed into the folder). `intent` = `"The method read out of #{n_steps} documents, in #{n_movements} parts. It is meant to tell somebody building the same thing what to do and in what order, so the test of any paragraph is whether it could be acted on."`. `body` = join with `"\n\n"` of: `[opening || ""]`, one block per movement `i` (from 1): lines `["## #{i}. #{heading}", "", prose, "\n> #{turn}" (only if turn non-empty)]` joined `"\n"`, then the three strings `"## Closing"`, `""`, `closing || ""`; whole thing trimmed. (Because the three closing strings are joined with `"\n\n"` too, the result has `## Closing` followed by four newlines then the closing; reproduce literally.)

### 7.6 `scrub(text, where)`
DeepSeek tool-markup leak guard. Split `text` once on `<` followed by U+FF5C (fullwidth vertical bar `｜`). No match -> `{text, nil}`. Match -> `{trim(before), "#{where}: the model leaked its own tool-call markup; the text was cut there"}`. Non-binary input -> `{text, nil}`.

### 7.7 Tool schemas
Verbatim in section 13.

---

## 8. Cases (`cases.ex`, `cases/*`)

A "case" is a named **collection**: works sharing `works.collection` (a string), ordered by `collection_role`. `@order = ["opinion","concurrence","dissent","argument"]`; `rank(role)` = index in `@order`, unknown/nil = 4.

| function | behavior |
|---|---|
| `slug(name)` | lower, replace `[^a-z0-9]+` (unicode flag) with `-`, trim `-` (no length cap, no fallback) |
| `place(work, collection, role)` | invalidate cache `:published_cases`; `Work.changeset(%{collection, collection_role})` update |
| `published()` | cached (5 min) under `:published_cases`: `list(owner.id)` for `Accounts.owner()`, else `[]` |
| `list(user_id)` | user's works with non-nil `collection`, ordered by `collection` asc, `id` asc. `kin = kinships(works)`; `{links, edges} = links_and_edges(works)` (all links touching any of those works with works preloaded; edges grouped by `link_id`, ordered `ordinal`,`id`, with `from`,`to` preloaded). Group works by collection and for each name call `assemble` + `kin: kin[name] || []`; sorted by `name` |
| `get(user_id, slug)` | find in `list(user_id)` by `slug` |
| `assemble(name, works, {links, edges})` | works sorted by `rank(collection_role)` (stable); `links` = those with both works inside the collection; `by_link` = `%{link_id => edges}`; map `%{name, slug, works, links, by_link, holding: holding(opinion work), read: #works status read, words: sum word_count, edges: total edges, missing: unlinked pairs (a.id < b.id) of works with no link between}` |
| `kinships(works)` | links with `status == "linked"` touching the works; edge counts from `link_edges` grouped by link (global query); for links where both works are in the set, collections **differ**, and count > 0, produce two entries (one per collection): `%{link_id, lead, other, case: other.collection, edges: n}` sorted by `-edges`; result `%{collection => [..]}` |
| `kin(c)` | `c[:kin] || []` |
| `ways(c)` | for links of the case with `status == "linked"` and both works found: `{lead, other}` ordered so lower `rank` is lead (ties: a is lead); `%{link, lead, other, edges: count}`; drop zero-edge; sort by `{rank(lead.role), -edges}` |
| `preview(c)` | `%{summary: first non-nil Links.summary(link) over links, sharpest: first 3 edges sorted by rank_edge (tension 0, answers 1, requires 2, other 3; stable), kinds: frequencies of edge_type sorted by -count, impression: opinion work's first_impression}` |
| `default_lead(c)` | the `opinion` work, else first work |
| `roles()` | `@order` |
| `reading(c, lead_id)` | nil if lead not in case. `inside` = linked links of the case touching the lead, each `%{link, work: other, elsewhere: nil}` sorted by rank of the other's role; `elsewhere(lead, c.name)` = lead's linked links (via `Links.for_work`) whose other work has a collection different from this case's, `%{link, work, elsewhere: other.collection}` sorted by that collection; `sources = inside ++ elsewhere`; `notes` = for each source `Links.margin(link, lead.id)` with each note extended by `from_work, from_title, from_role, from_case, link_id`; result `%{lead, sources, notes, page: Reading.page(lead, notes: notes)}` |

**`holding(work)`** (pure; lifts the Court's holding from the opinion): `nil` -> nil. `flat = body with whitespace runs -> single space`. Try these four regexes in order, first one that matches wins (leftmost match in `flat`):
1. `\b[Ww]e (?:therefore |accordingly |now )?hold that\b[^.]{20,300}\.`
2. `\b[Ww]e (?:therefore |accordingly |now )?conclude that\b[^.]{20,300}\.`
3. `\b[Ww]e (?:hold|conclude)\b[^.]{20,300}\.`
4. `\bWe (?:therefore |accordingly )?(?:reverse|affirm|vacate)\b[^.]{10,300}\.`
Widen the match backwards to the start of its sentence: `before = flat[0, at)`; find all matches of `[.!?][”"]?\s+` in `before`; `start` = end of the last one (or 0). `text = flat[start, at+len)`. Then repeatedly strip a leading division marker with `^\s*(?:[IVXL]{1,5}|[A-Z]|\d{1,2}|\*(?:\s*\*)*)[\s.]+` until nothing changes (stop and keep the previous text if stripping would yield ""). Finally trim. No match -> nil (no fallback).

**`Cases.Record`**: static map name -> `%{docket, argued, decided[, question]}` for 16 US Supreme Court cases, accessed by `Record.for(name)` (nil if absent) and `names/0`. Data (docket / argued / decided; `question` only where listed):
Blanche v. Lau: No. 25-429, April 22 2026, June 23 2026. Chatrie v. United States: No. 25-112, April 27, June 29; question "Whether a geofence warrant compelling Google to disclose the Location History of every device in an area is a Fourth Amendment search." Cisco Systems v. Doe: No. 24-856, April 28, June 23. Exxon Mobil Corp. v. Corporacion Cimex: No. 24-699, February 23, June 23. Landor v. Louisiana: No. 23-1197, November 10 2025, June 23 2026; question "Whether RLUIPA, enacted under the Spending Clause, lets a prisoner sue a state official for damages in their individual capacity." Monsanto Co. v. Durnell: No. 24-1068, April 27, June 25. Mullin v. Al Otro Lado: No. 25-5, March 24, June 25. Mullin v. Doe: No. 25-1083, April 29, June 25. National Republican Senatorial Committee v. FEC: No. 24-621, December 9 2025, June 30 2026. Pung v. Isabella County: No. 25-95, February 25, June 23. T. M. v. University of Maryland Medical System: No. 25-197, April 20, June 18. Trump v. Barbara: No. 25-365, April 1, June 30. Trump v. Slaughter: No. 25-332, December 8 2025, June 29 2026; question "Whether a President may remove a Federal Trade Commission commissioner before the end of their term, and whether Humphrey's Executor survives." Watson v. Republican National Committee: No. 24-1260, March 23, June 29. West Virginia v. B. P. J.: No. 24-43, January 13, June 30; question "Whether Title IX or the Equal Protection Clause bars a State from limiting girls' school sports teams to students assigned female at birth." Wolford v. Lopez: No. 24-1046, January 20, June 25. (All 2026 except where a year is written; argued dates in Nov/Dec 2025 as shown. Dates are strings, e.g. `"April 22, 2026"`.)

**`Cases.Kinship`** (pure; **no caller in `lib/`**, tests only). Constants: `@min_df 2`, `@max_share 0.33`, `@min_len 5`, `@min_tf 2`.
* `terms(text_parts)`: drop nil/`""` parts; join `" "`; lowercase; replace `[^\p{L}\s]+` (unicode) with `" "` (digits, underscores, punctuation vanish); split on whitespace; `singular` each; drop words with grapheme length `< 5` or in the stop list; count frequencies; keep words with count `>= 2`; return as a set.
  `singular(w)`: if ends `"ies"` and length > 5 -> drop last 3 chars + `"y"`; elif ends `"sses"` -> drop last 2; elif ends `"s"` and not `"ss"` -> drop last 1; else unchanged.
  Stop list: `about above after again against all also and any are because been before being below between both but cannot could did does doing down during each few for from further had has have having her here hers him his how into its itself more most nor not now off once only other ought our out over own same she should some such than that the their them then there these they this those through too under until very was were what when where which while who whom why will with would you your court courts case cases opinion opinions held holding justice justices argument arguments dissent dissents concurrence majority section sections paragraph draft manuscript reader writing writes argues argued argue claims claim point points question questions says said say reads read whether because therefore however`.
* `pairs(bags, limit \\ 12)`: `bags` = `%{id => set}`. `n = #bags`; `df[t]` = number of bags containing t; `max_df = max(trunc(n * 0.33), 2)`; `keep` = terms with `2 <= df <= max_df`, weight `ln(n / df)`. For ids sorted ascending, every pair `a < b`: `shared = (bag_a ∩ bag_b) ∩ keep`; `weight = Σ keep[t]`; `size = sqrt(|bag_a| * |bag_b|)` (set sizes before filtering); `score = weight / size` (0.0 if size is 0). Reject score 0.0; sort by `-score`; take `limit`. Each result `%{a, b, score, shared}` where `shared` = shared terms sorted by weight descending, first 8 (ties unspecified in the original; sort by term for determinism). Example: bags of `alien/border`, `glyphosate/labeling`, `citizenship`, `sovereign` pair 1-2 and 3-4 only; a huge document does not beat a clean pair.

**`Cases.Chat`** (`cases/chat.ex`): same shape as `Links.Chat` (call #3): messages `[system SYSTEM, system card(reading)] ++ history ++ [cited_card]`, `LLM.chat(provider, model: default_model(provider), effort: :low, temperature: 0.5, max_tokens: 4000)`; `{:ok, text}` iff non-empty content else `{:error, :empty_reply}`. `edges(reading)` = `[{source, edge}]` over `Links.edges(source.link)` for all sources. Documents are named, never lettered: `name(work)` = title after the first `" — "`, else title. `whose(node, reading, s)` = (`name(lead)` if `node.work_id == lead.id`, `name(s.work)` if `== s.work.id`, else `"another document"`) `<> " — " <> node.title`. `from_case(%{elsewhere: nil})` = `""`, else `" (from #{name}, a different case)"`.
`card(reading)`:
```
# THE DOCUMENT BEING READ

#{name(lead)} — #{lead.word_count} words

# READ AGAINST (#{n_sources})

#{sources: "- #{name(s.work)} — #{s.work.word_count} words#{from_case(s)}" + ("\n    #{Links.summary(s.link)}" if link.summary) joined "\n"}

# THE CONNECTIONS (#{n_edges})

#{edges: "- #{whose(e.from)} --#{e.edge_type}--> #{whose(e.to)}\n    #{e.rationale}" joined "\n"}

# MAP OF #{UPPERCASE(name(lead))}
#{map(lead)}
#{sources: "\n# MAP OF #{UPPERCASE(name(s.work))}#{from_case(s)}\n#{map(s.work)}" joined "\n"}
```
`map(work)` as in Links.Chat but node lines are `"- #{title}" <> (" (§#{ordinal})" if section) <> ("\n    \"#{one_line(quote)}\"" if quote)` (no node ids). `cited_card(reading, edge_ids)`: same preamble as Links.Chat's; blocks `## #{UPPERCASE(type with _ -> space)}#{from_case(s)}\nWhy it was drawn: #{rationale}\n\n### #{whose(e.from)}\n#{Links.passage(e.from)}\n\n### #{whose(e.to)}\n#{Links.passage(e.to)}\n` joined `"\n\n"`. `passes/0` metadata id `"case_chat"`, name `"Talking about a case"`, runs `"per message, on a case being read"`, produces `"answers about how the documents of a case sit together"`. `for_case(c, lead_id)` = `Cases.reading`.

---

## 9. Import

### 9.1 `Marginalia.Import.fetch(url, opts \\ [])` -> `{:ok, %{title, markdown, url}} | {:error, reason}`
Pipeline: `allowed(url)` -> `get` -> `parse` -> `title` + `article` -> markdown. `opts[:body]` (binary) bypasses the network (tests). Constants: `@max_bytes 4_000_000`, `@timeout 20_000`.

**`allowed(url)`** (security boundary): non-binary -> `{:error, :bad_url}`. `uri = URI.parse(trim(url))`; scheme not `http`/`https` -> `:bad_scheme`; host nil/`""` -> `:no_host`; `private?(host)` -> `:private_address`; else `{:ok, uri}`.
`private?(host)`: lowercase, strip trailing `.`; true if host in `localhost, 0.0.0.0, broadcasthost`; or ends with `.localhost`, `.local`, `.internal`; if it parses as an IP literal (`:inet.parse_address`, IPv4 or IPv6) -> `reserved?`; otherwise resolve with `:inet.getaddrs(host, :inet)` (**IPv4 only**) and refuse if any address is reserved or if resolution fails.
`reserved?` IPv4: `127.*`, `10.*`, `192.168.*`, `169.254.*`, `172.16-31.*`, `0.*`, `100.64-127.*` (CGNAT), first octet `>= 224`. IPv6: `::1`, `fc00::/7` (first group 0xFC00..0xFDFF), `fe80::/10` (0xFE80..0xFEBF); all other IPv6 -> not reserved (so `::`, `::ffff:127.0.0.1` pass — a gap).
Not enforced: the **redirect targets** are never re-checked (see S2).

**Request**: `Req.get(url)` with `receive_timeout 20000`, `max_redirects 3`, `redirect_log_level false`, `max_retries 1` (Req default retry mode `:safe_transient` for GET: retries 408/429/500/502/503/504 and `timeout/econnrefused/closed` once, with Retry-After or ~1s jittered backoff), headers `user-agent: Marginalia/1.0 (+https://marginalia.bobbby.online)`, `accept: text/html,application/xhtml+xml`. Result: status 200 with a **binary** body -> `{:error, :too_big}` if `> 4_000_000` bytes else the HTML; any other status (including a JSON-decoded 200) -> `{:error, {:http, status}}`; transport error -> `{:error, :unreachable}` (logs a warning). `Floki.parse_document` failure -> `:unparseable`.

**title(doc)**: candidate list in order — text of the first `article h1`; text of the first `h1`; every `content` attribute of `meta[property='og:title']`; text of `title`. Each `clean`ed (`squash` then trim); first non-empty, else `"Untitled"`; truncated to 200 chars.
**article(doc)**: remove all elements whose tag is in `script style nav header footer aside form noscript svg iframe button figure figcaption template`; candidates = every element matching, in this order of selectors, `article`, `main`, `[role=main]`, `.post`, `.entry-content`, `body`; choose the one with the longest `Floki.text` (first wins ties); none -> the whole document.
**to_markdown(node)**: walk children in document order; an element whose tag is in `h1..h6 p ul ol blockquote pre` is a block (and not descended into); any other element is descended; text nodes/comments at that level are ignored. Blocks rendered then joined `"\n\n"`, empties dropped, 3+ newlines collapsed to 2, plus a trailing `"\n"`:
* `hN`: `"#" x N + " " + inline`, nil if empty text.
* `p`: inline (nil if empty). `blockquote`: inline with each line prefixed `"> "` (inline never contains newlines, so one line).
* `pre`: `Floki.text` trimmed, wrapped `"```\n" + code + "\n```"` (no language).
* `ul`/`ol`: **all** descendant `li` (nested lists are flattened) rendered inline, empties dropped; `ol` -> `"1. x"`, `"2. y"` by position; `ul` -> `"- x"`; joined `"\n"`.
* inline(node): children rendered and concatenated, then `clean`. Render: text as is; `strong`,`b` -> wrap `**`; `em`,`i` -> wrap `*`; `code` -> wrap `` ` ``; `br` -> `" "`; `a` -> `[text](href)` unless text empty (`""`) or href empty or starting `#` (just text); `sup` -> `""`; any other element -> `inline(el)` (which trims — so spacing around an unknown inline element is lost).
* wrap(el, mark): render children, `squash`; if trimmed text empty -> `""`; else keep a single leading/trailing space **outside** the marks: `lead <> mark <> text <> mark <> trail`.
* `squash(text)`: `[\x{00a0}\x{200b}\t ]+` -> `" "`, then `\s*\n\s*` -> `" "`. `clean` = squash + trim.
**Assembly**: `markdown = to_markdown(article) |> drop_leading_title(title)`: if the first block (split on first `"\n\n"`) starts with `"# "` and `similar?(heading_text, title)` (both reduced to letters/digits only lowercase; non-empty and one contains the other) it is removed. `String.length(markdown) < 400` -> `{:error, :too_little_text}` (measured before the title is re-added). Else `{:ok, %{title, markdown: "# " <> title <> "\n\n" <> markdown, url: URI.to_string(uri)}}`. (Title is never empty: `"Untitled"` fallback.)

### 9.2 `Import.Query` (query box over fetched PR candidates)
Candidate map keys used: `repo, number, title, state ("open"|"closed"|"merged"), draft, base, head, created_at, updated_at, merged_at` (ISO8601 strings or nil).
* `filter(candidates, text)` -> `{:ok, kept}` | `{:error, message}`: `parse` then keep candidates for which **all** terms hit; empty term list keeps everything.
* `parse(text)` -> `{:ok, [term]}` | `{:error, msg}`. Tokens: regex `"[^"]*"|\S+` over the text, dropping `""` and `""""` (empty quotes). Term per token: leading `-` negates the rest (`{:not, term}`; a negated no-op stays a no-op). Split on first `:`: no colon -> text term; colon at position 0 -> text term of the whole token; else qualifier `(key.downcase, value)`. Values and text have surrounding `"` trimmed then whitespace trimmed. Text term = case-insensitive substring of the title.
* Qualifiers (key case-insensitive; **value case-sensitive** except where lowercased):
  * `is:pr` no-op; `is:issue` -> error `` `is:issue` — there are only pull requests here. ``; `is:draft` -> draft true; `is:open|closed|merged` -> state; other `is:v` -> `` `is:v` — I know is:pr, is:draft, is:open, is:closed and is:merged. ``
  * `state:open|closed|merged`; other -> `` `state:v` — a pull request here is open, closed or merged. ``
  * `draft:true|yes|false|no`; other -> `` `draft:v` — true or false. ``
  * `repo:`, `base:`, `head:` -> exact match, lowercased on both sides.
  * `number:` comparison over integers; error `` `number:v` — a number, or >100, <100, 10..20. ``
  * `created:`, `updated:`, `merged:` -> comparison over dates on field `created_at|updated_at|merged_at`; error `` `key:v` — BAD is not a date. Write 2025-08-05, or @today, or @today-30d, and compare with > < >= <= or a .. range. `` (BAD = the offending piece).
  * unknown key -> `` `key:v` — I do not know the qualifier `key`. I know is, state, draft, repo, base, head, number, created, updated, merged, and a bare word matches the title. ``
* Comparison syntax: `>=x`, `<=x`, `>x`, `<x` (checked in that order), else `a..b` (`*` open end: `a..*` -> `>=a`, `*..b` -> `<=b`), else exact. Hit rules: `state` compares `(c.state || "open")`; `draft` is `c.draft == true` equals wanted; `number` numeric; dates compare the first 10 chars of the stored ISO string as a `Date`, **a nil/unparseable date fails every comparison** (even negated ones succeed only via `-`).
* `date(raw)` / `date(raw, today)`: trims; `"@today"` -> today (UTC); `"@today" + [+-]N + d|w|m|y` (regex `^([+-])(\d+)([dwmy])$`) -> days, 7*weeks, calendar months, 12*months; months clamp the day to the target month's last day (`2025-03-31` `-1m` -> `2025-02-28`); otherwise ISO date `YYYY-MM-DD`; anything else `:error`. `@today` must be lowercase here.
* `expand(text)`: replace `@today(?:[+-]\d+[dwmy])?(?![\w-])` (case-insensitive) with the ISO date (token lowercased for evaluation); an unparsable token is left untouched. Used on queries sent to GitHub. `@today-3fortnights` is left as is.
* `hint(text)`: regex `\b(created|updated|merged):([^\s<>=]\S*)` first match; if the value has no `..` -> `%{was: "key:value", try: "key:>value"}` else nil. (Warns that a bare date is an exact day.)

### 9.3 `Import.GitHub`
Constants: API `https://api.github.com`, timeout 20000 ms, `per_page 100`, max pages 5, file cap 100, `@files_shown 60`, `@commit_cap 7000`. Request helper `get(path, token)` = `Req.get(api <> path, headers, receive_timeout: 20000)` (Req defaults: auto-JSON decode, up to 3 retries with backoff on 408/429/5xx/transport per `:safe_transient`, max 10 redirects).
Headers: `accept: application/vnd.github+json`, `x-github-api-version: 2022-11-28`, `user-agent: marginalia`, and `authorization: Bearer <token>` **only if the token (trimmed) is non-empty**. The token is supplied per request by the user (form field), never stored, no env var.
Result mapping: 200 -> `{:ok, body}`; 401 -> `{:error, :unauthorized}`; 403/429 -> `{:error, :forbidden}` unless header `x-ratelimit-remaining` is `"0"` in which case `{:error, {:rate_limited, reset_header_or_nil}}`; 404 -> `:not_found`; 422 -> `{:error, {:rejected, errors[0].message || message || nil}}`; other -> `{:error, {:http, status}}`; transport -> `{:error, {:transport, inspect(reason)}}`.
Names: `check_name(s)` must match `^[A-Za-z0-9._-]{1,100}$` else `{:error, :bad_name}`.
Endpoints: `GET /repos/{o}/{r}` (field `default_branch`; missing -> `:no_default_branch`); `GET /repos/{o}/{r}/pulls?state={s}&per_page=100&page={1..5}`; `GET /repos/{o}/{r}/pulls/{n}`; `GET /repos/{o}/{r}/pulls/{n}/commits?per_page=100` (first page only); `GET /repos/{o}/{r}/pulls/{n}/files?per_page=100` (first page only); `GET /search/issues?q={URI.encode_www_form(q)}&per_page=100&page={1..pages}`.
Pagination (both pulls and search): stop on an empty page; stop after a page with `< 100` items (keeping it); otherwise continue; at most 5 pages (500 items); an error aborts the whole listing.
* `stack(owner, repo, token, opts)`: default branch, `pulls` (state `opts[:state] || "open"`), `order(pulls, default)`, then `with_commits` for each item sequentially. Returns `{:ok, [%{ordinal, number, title, body, url, commits}]}`. (`with_files` is **not** used here.)
* `order(pulls, default)`: `[]` -> `{:error, :no_pull_requests}`. Duplicate `head.ref` among pulls -> `{:error, {:duplicate_branches, sorted_refs}}`. Roots = pulls with `base.ref == default`: 0 -> `{:error, {:no_root, default}}`; >1 -> `{:error, {:many_roots, [numbers]}}`; exactly 1 -> walk: from the root repeatedly pick the pull whose `base.ref` equals the current pull's `head.ref` (map keyed by base ref; later pulls overwrite earlier with the same base), stopping when none or a number repeats. Pulls not visited -> `{:error, {:off_chain, [numbers]}}`; else `{:ok, items}` with `ordinal` 1.. , `body || ""`.
* `list(owner, repo, token, opts)`: pulls with state `opts[:state] || "all"`, each via `candidate("owner/repo", p)`.
* `search(query, token, opts)`: blank -> `{:error, :empty_query}`; `q = Query.expand(trim(q))`; append `" is:pr"` unless the string contains `is:pr`; pages `min(opts[:pages] || 5, 5)`; response must be a map with `"items"` else `{:error, :no_results_field}`; each item -> `candidate(repo_of(item), item)` where repo = text after `/repos/` in `repository_url`.
* `candidate(repo, p)` -> `%{repo, number, title (""), url: html_url, state, draft (== true), base: base.ref, head: head.ref, updated_at, created_at, merged_at}`; `state` = `"merged"` if `merged_at` (top-level or under `pull_request`) is a string, else `p["state"] || "open"`.
* `oldest_first(candidates)`: sort by `{merged_at || created_at || "", number || 0}` ascending.
* `documents(candidates, token, opts)`: options `commits` (default true), `files` (default true), `concurrency` (default 6), `on_item.(candidate, total)`. `Task.async_stream` (`max_concurrency`, `timeout 120000`, `on_timeout :kill_task`, ordered). Each: split `repo` on `/`, `check_name` both, `GET pulls/{n}`; item `{title: full.title || c.title, body: full.body || "", url: full.html_url || c.url, changed_files}`, plus commits then files if enabled; doc = `%{number, repo, title, body: document(item), source_url: url}`. Returns `%{documents: [...], failed: [{candidate, reason}]}`; a crashed task gives reason `{:crashed, inspect(exit)}`; a bad repo string gives `:bad_name`.
  `with_commits`/`with_files`: on non-list/failed response set `commits`/`files` to `{:error, other}` where `other` is the whole `{:error, ...}` tuple (so the inspect in the document shows a doubly wrapped tuple), log a warning. Commit map `%{sha: first 8 chars, message: trim(commit.message)}`; file map `%{path: filename, was: previous_filename, status, added: additions||0, removed: deletions||0}` (patch hunks are dropped on purpose).
* `document(item)`: `writeup` = trimmed body or, if empty, `"_This pull request (##{number}) has no description._\n\n#{url}\n"`; result `writeup <> file_list(item) <> commit_trail(commits)`.
  * `file_list`: files `[]` or missing -> `""`; `{:error, r}` -> `"\n\n---\n\n## Files changed\n\n_The file list could not be fetched (#{inspect(r)}), so this says nothing about what was touched._\n"`; else `total = changed_files || length(files)`, `shown` = first 60; header `"## Files changed (#{head})"` with `head = "#{total}, the first #{n_shown} listed"` if `n_shown < total` else `"#{total}"`; text `"\n\n---\n\n## Files changed (#{head})\n\n" <> lines joined "\n"`. Line: renamed -> `` - `was` → `path` `` + counts; added -> `` - `path` `` + counts + ` — new`; removed -> ``- `path` `` + counts + ` — deleted`; else `` - `path` `` + counts. counts: both 0 -> `""`; `" +A"` if removed 0; `" −R"` (U+2212 minus) if added 0; else `" +A −R"`.
  * `commit_trail`: `[]` -> `""`; `{:error, r}` -> `"\n\n---\n\n## Commits\n\n_The commit trail could not be fetched (#{inspect(r)}), so this chapter is its description alone._\n"`; else `"\n\n---\n\n## Commits (#{count})\n\n" <> trail <> "\n"` where each commit `"### #{subject}  (#{sha})"` (two spaces before the paren) plus `"\n\n#{detail}"` if the rest of the message after the first line is non-empty (trimmed), commits joined `"\n\n"`, the whole trail truncated to 7000 chars with `"\n\n_[commit trail truncated]_"` appended when longer.
* `import_stack(user_id, owner, repo, token, opts)`: `stack(...)` then folder named `opts[:folder] || "owner/repo"` (find the user's folder with that exact name in **any** parent, else create at root; creation error -> that error). Titles in the folder form the existing set. For each item whose `title_for(item)` is not in the set: `Works.create_work(user, %{"title","body" => document(item),"source_url" => url})` (**must succeed**: `{:ok, work} =` match raises otherwise), `Folders.move_work`, then `opts[:on_item].(item, n_items)`. `title_for` = title unchanged if it already starts with `^\s*\d+\s*[.):-]`, else `"#{ordinal}. #{title}"`. Returns `{:ok, %{folder, created: count, total}}`.
* `explain(reason)` messages (exact):
  * `{:many_roots, nums}`: `"#{n} pull requests are based on the default branch (##{nums joined ", #"}). That is more than one stack, and this cannot tell which you meant."`
  * `{:no_root, b}`: `"No open pull request is based on #{b}, so there is no start to the chain."`
  * `{:off_chain, nums}`: `"#{n} pull request(s) are not on the chain: ##{nums joined ", #"}. A stack is each one based on the one before it."`
  * `{:duplicate_branches, refs}`: `"More than one open pull request comes from the same branch (#{refs joined ", "}). A stack is one pull request per branch."`
  * `:no_pull_requests`: `"That repository has no open pull requests."`; `:empty_query`: `"Write a search query first."`
  * `{:rejected, nil}`: `"GitHub would not run that search. Check the qualifiers and the dates."`; `{:rejected, said}`: `"GitHub would not run that search: #{said}"`
  * `:no_results_field`: `"GitHub answered the search with something this does not recognise."`; `{:crashed, _}`: `"That one crashed on the way in."`; `:unauthorized`: `"GitHub rejected the token."`
  * `:forbidden`: `"GitHub refused: the token may lack access, or you are rate limited. Without a token that is 60 requests an hour, and 10 searches a minute."`
  * `{:rate_limited, reset}`: `"GitHub is rate limiting this. " <> back_at(reset) <> " Without a token the allowance is 60 requests an hour; with one it is 5000, and a hundred pull requests is three hundred requests."` where `back_at(nil)` or unparsable = `"Give it a few minutes."`, else `"It comes back at HH:MM UTC, in #{div(wait,60)}m#{rem(wait,60)}s."` (`wait = max(reset_unix - now, 0)`).
  * `:not_found`: `"No such repository, or the token cannot see it."`; `:bad_name`: `"Owner and repository must look like GitHub names."`; `{:http, s}`: `"GitHub answered #{s}."`; `{:transport, _}`: `"Could not reach GitHub."`; other: `"Import failed: #{inspect(other)}"`.

### 9.4 `Import.Bulk` (landing a pile)
* `land(user_id, docs, opts)`: `docs` = `%{title, body, source_url?}`. Options `:folder` (name), `:number`, `:on_item.(title, i, total)`. Folder: nil/blank -> loose (nil); else the user's folder with that exact name in any parent (`Repo.one` — raises if several share it), else `Folders.create_folder`, falling back to loose on error. `have` = titles currently in the folder (snapshot taken once; duplicates within the same batch are not detected). For each doc with index `i` from 1: `title` (see below); in `have` -> skipped; else `Upload.prepare(title, body, nil)` (word gate: empty -> `:empty`; `> 120_000` words -> `{:too_long, n}`; attrs `title` (or "Untitled draft"), `body`, `intent` nil) then add `"source_url"` and `Works.create_work`; if a folder, `Folders.move_work`. Errors: changeset -> `"#{field} #{message}"` of the first error (or `:invalid`); gate errors as is. `on_item` is called after every doc (also skipped/failed). Returns `%{folder, created: [works], skipped: [titles], failed: [{title, reason}]}`.
  `title_for`: `clean(doc.title)` = nil -> `"Untitled"`; whitespace runs -> single space; trim; empty -> `"Untitled"`; first 200 chars. With `:number` truthy: unchanged if it matches `^\s*\d+\s*[.):-]`, else `"#{i}. #{title}"` (`i` is the position in the list).
* `explain(reason)`: `:empty` -> `"there is no text in it"`; `{:too_long, w}` -> `"#{w} words, over the limit"`; `:no_sections` -> `"no text that could be split into sections"`; binary -> itself; else `inspect`.
* `by_title(candidates, pattern)`: blank pattern -> all; `Regex.compile(pattern, "i")`; compile error -> `{:error, "#{reason} at character #{at}"}` (or `inspect`); else keep those whose title (first **200** chars) matches.
* **main only** `folder_name_for(titles, now \\ utc_now)`: stem = longest common prefix of the titles (by grapheme), then strip trailing `[\s\d._-]+`, trim; if `length(stem) >= 3` -> stem else `"Imported " <> strftime(now, "%Y-%m-%d %H:%M")`. (Single title: the title itself, so `"chapter-01"` -> `"chapter"`. `["Part 1","Part 2"]` -> `"Part"`; `["alpha","omega"]` -> `"Imported 2026-09-22 14:54"`.) **main only** `in_name_order(docs)`: natural sort by lowercased title split on `(\d+)` with captures; digit parts compare numerically and sort before text parts: part key `{0, n, ""}` for pure digits else `{1, 0, text}`.

### 9.5 Git (`git.ex`)
See 9.7.

### 9.6 Web fetch summary
`Import.fetch` uses Req + Floki (above). The GitHub client uses Req only. No other outbound HTTP exists in this layer besides the LLM client.

### 9.7 `Marginalia.Git` (local history per draft; **no clone**)
Off unless config `:draft_repo_root` (env `DRAFT_REPO_ROOT`, no default) is a non-empty string. `enabled?/0`, `root/0`, `path(work)` = `Path.join(root, work.slug)` (nil when disabled). All functions return `{:error, :not_configured}` when disabled.
Binary: `git` on `PATH`. Every command via `System.cmd("git", args, cd: dir, stderr_to_stdout: true)`; exit 0 -> `{:ok, output}`, else log warning and `{:error, {:git, code, first 300 chars of output}}`.
* `commit(work, message, opts)`: `ensure_repo` (if `<dir>/.git` missing: `mkdir -p dir`, then `git init --quiet --initial-branch=main`, `git config user.name Marginalia`, `git config user.email marginalia@localhost`); write `draft.md` with contents `"---\ntitle: #{title}\nslug: #{slug}\nwords: #{word_count}\n---\n\n#{body}\n"`; `git status --porcelain` empty -> `{:ok, :unchanged}`; else `git add draft.md`, `git commit --quiet --message <subject> [--author <opts[:author]> if non-empty string]`, `git rev-parse --short HEAD` -> `{:ok, trimmed_sha}`. `subject`: whitespace runs -> single space, trim, first 200 chars, empty -> `"Edit"`.
* `log(work, limit \\ 50)`: `{:error, :no_repo}` if no `.git`; `git log --max-count=<limit> --pretty=format:%h%x1f%ad%x1f%s --date=iso`; lines split on `\n`, fields on `\x1f` -> `%{sha, date, subject}` (malformed lines dropped).
* `show(work, sha)`: sha must match `^[0-9a-f]{4,40}$` else `{:error, :bad_sha}`; `git show --format=%h %ad%n%s%n --date=iso <sha>` (single argument string `--format=%h %ad%n%s%n`) -> raw output.
* `record(work_id, message, opts)`: disabled -> `{:error, :not_configured}`; requires `opts[:user_id]` (raises otherwise); `Works.get_work!(user_id, work_id)` then `commit`.
* Callers run commits fire-and-forget under `TaskSupervisor` after an accepted edit (author `"<email> <email>"`). Repositories are never deleted.

---

## 10. Mutterings (branch `main` only)

Purpose: a short in-character line shown in front of the "three dots" while a model is thinking. Lines are themselves model-written, stored in `mutterings`, and picked at random. Nothing a page does waits on the model to show one: an empty table means "dots only".

Module `Marginalia.Mutterings`. Constants: `@seed 100`, `@batch 10`, `@max_chars 240`, `@remember 40`. `prompt/0` is the system prompt (verbatim in 13.8).
* `one()` -> one random row's text (`ORDER BY random() LIMIT 1`) or nil.
* `some(n)` (n > 0): up to `n` random distinct lines excluding those in the calling **process's** memory (`Process` dictionary key `:mutterings_seen`, a list). If the pick is empty while memory is non-empty, clear memory and pick again. Memory := first 40 of `picked ++ seen`. Returns `[]` if the table is empty. (Port: keep this memory per page/session, not global.)
* `count()`.
* `seed(opts)`: up to 4 rounds; each round `missing = 100 - count()`; if `> 0`, `generate(missing, source: "seed")`, accumulating the added count; `{:ok, added}` when nothing is missing; an error on the first round (nothing added yet) is returned as `{:error, e}`, an error later returns `{:ok, added_so_far}`.
* `topup(opts)` = `generate(opts[:count] || 10, source: "cron")`.
* `generate(n, opts)`: `call = opts[:call] || ask`; `{:ok, text} = call(n)`; `parse(text)` take `n`; rows `%{text, source (default "cron"), inserted_at, updated_at}`; none -> `{:error, :nothing_usable}`; else `insert_all` with `on_conflict: :nothing, conflict_target: :text` -> `{:ok, rows_inserted}` (duplicates are skipped, not errors). A `call` error is returned unchanged.
* `parse(text)`: nil -> `[]`; split on `\r?\n`; per line `clean`: trim; strip one leading bullet/number `^(?:[-*•]|\d+[.)])\s*`; trim; strip leading run of quote chars `["“„'‘]+` and trailing run `["”'’]+` (two separate anchored regexes in one replace: `^["“„'‘]+|["”'’]+$`); trim. Reject empty lines, lines ending in `:`, lines longer than 240 characters; `uniq` preserving order.
* `ask(n)`: LLM call #9. Reply must have `message["content"]` binary else `{:error, {:no_content, message}}`.
Schema `Mutter`: `text`, `source` (default "cron"), timestamps.

`Marginalia.Mutterings.Clock` (GenServer, registered name = module): options from `config :marginalia, Marginalia.Mutterings.Clock` merged with `start_link` opts: `enabled` (default true; test sets false -> `init` returns `:ignore`), `every` (default 30 minutes), `first` (default 5 s), `call` (replacement for the model, tests). `init` schedules `:tick` after `first`. On `:tick`: if there is no `call` override and `LLM.configured?()` is false -> do nothing this tick; elif not yet `seeded` -> run `Mutterings.seed(...)`, on `{:ok, n}` log `"marginalia mutterings: seeded n"` and set `seeded: true`, on error stay unseeded; else run `Mutterings.topup` and log `"marginalia mutterings: added n"`. Always reschedule `:tick` after `every`. Every call is wrapped: an error or exception logs a warning `"marginalia mutterings: ..."` and the next tick happens. It never crashes the app. **This is the only periodic job in the system.**

---

## 11. Background work

### 11.1 `Marginalia.Runs` (GenServer + public ETS table `:marginalia_runs`)
Purpose: long jobs that must outlive the browser tab. One entry per key, one running job per key.
* `start(key, kind, fun)`: if `key` already has an entry -> `{:error, {:already_running, existing_kind}}`. Else start `fun` with `Task.Supervisor.async_nolink(Marginalia.TaskSupervisor, fun)`, store `run = %{kind, done: 0, total: nil, stage: nil, pid, started_at: utc_now}`, broadcast `{:run, :started, run}`; returns `{:ok, run}`.
* `progress(key, fields)` (cast, fire-and-forget): merge `fields` (`done`, `total`, `stage`) into the run; ignored if no run; broadcast `{:run, :progress, run}`.
* `get(key)` (ETS read in caller), `running?(key)`, `forget(key)` (deletes the entry, leaves the task), `subscribe(key)`.
* PubSub topic: `"run:" <> inspect(key)`, e.g. `"run:{:stack, 12}"`, on `Marginalia.PubSub`.
* Completion: task returned `result` -> delete entry, broadcast `{:run, :done, kind, result}`. Task died -> delete entry, log warning `"marginalia: run <key> (<kind>) died: <reason>"`, broadcast `{:run, :crashed, kind, reason}`. State lives in ETS only: **lost on restart**.
* Keys and kinds in use: `{:stack, folder_id}` with kinds `:read`, `:deepen`, `:summarise`, `:relate`, `:read_each`, `:compose`; `{:work, work_id}` with kind `:compare` (`Document.compare`, out of scope).
* Returned results (kept tiny): `:read`/`:deepen`/`:summarise`/`:read_each` -> `{:errors, n}`; `:compose` -> `:ok` or the error tuple; `:relate` -> `{:related, n_started, n_not_read}` or `{:error, reason}`; `:compare` -> `{:compared, link_id}` or `{:error, reason}`.
* Progress reported by pages: read: `done: i, total: #documents`; deepen: `done, total: stats.read`; summarise: `done, total: documents - summarised`; read_each: `done, total: documents - mapped`; compose: `stage` in `"outlining"`, `"writing"` with `done`/`total` parts (total nil while outlining); relate: `stage: "choosing the pairs"` then per pair `done: previous+1, total: #eligible pairs, stage: "relating"`; compare: `stage` strings from `Document.compare`.

### 11.2 Other detached work
| work | mechanism | state |
|---|---|---|
| link pair (`Linker.start/run`) | `Task.Supervisor.start_child` | `links.status` `pending|failed` -> `linking` -> `linked` or `failed` (`error` = `inspect(reason)`); PubSub topic `"link:#{link.id}"` messages `{:link,:start}`, `{:link,:stage,:reading|:asking|:checking}`, `{:link,:done}`, `{:link,:failed}` |
| bulk relate (`Links.Bulk.relate`) | `Task.async_stream` inside the `Runs` task, concurrency 3, per-pair timeout 300 s | creates `links` rows (pending) and runs Linker synchronously per pair |
| cut read (`Cuts.read`) | `start_async` on the LiveView (dies with the socket) | `cuts.status` `draft -> reading -> read|failed` |
| stack import / file import | `start_async` on the LiveView; progress via messages to the LiveView pid (not PubSub) | none persisted |
| GitHub `documents` | `Task.async_stream` concurrency 6, timeout 120 s | none |
| work read (`Analysis.start/run`) | `Task.Supervisor.start_child`, PubSub topic `Analysis.topic(work_id)` | `works.status` `pending -> reading -> read|failed` (out of scope) |
| git commit | `Task.Supervisor.start_child` after an accepted edit | none |
The stack-page passes (`read`, `read_each`, `summarise`, `deepen`, `compose`, `relate`) are sequential per document (parallelism only inside `relate` and inside `Document`/`Analysis`).

### 11.3 `Marginalia.Recovery` (boot sweep)
A temporary child whose `start_link` runs `sweep()` then returns `:ignore`; it starts after Repo/Cache/Runs and before the Endpoint. `sweep`: `UPDATE links SET status='failed', error='interrupted by a restart', updated_at=now WHERE status='linking'`; `UPDATE works SET status='failed', status_detail='interrupted by a restart', updated_at=now WHERE status='reading'`. Logs a warning with the counts if any. Returns `{links_n, works_n}`. It does **not** touch `cuts` (status `reading`) or `sections`.

### 11.4 `Marginalia.Cache` (GenServer owning public ETS `:marginalia_cache`)
`fetch(key, fun, ttl \\ 5 min)`: if an entry exists and `monotonic_now - stored_at < ttl` return it; else compute `fun.()`, store `{key, rows, now}` and return. `peek(key, ttl)` -> `{:ok, rows} | :miss`. `invalidate(key)`, `invalidate_all()` (both no-ops if the table is missing). Keys in this layer: `:public_links`, `:published_cases`. Invalidation sites: `Links.get_or_create` (new pair only), `Links.store_edges`, `Links.clear_edges`, `Cases.place`. Empty results are cached too.

---

## 12. Application, release, config

### 12.1 Supervision tree (`Marginalia.Application`, strategy `:one_for_one`, name `Marginalia.Supervisor`), in start order
1. `MarginaliaWeb.Telemetry`
2. `Marginalia.Repo` (Ecto Postgres)
3. `{DNSCluster, query: config :dns_cluster_query || :ignore}`
4. `{Phoenix.PubSub, name: Marginalia.PubSub}`
5. `{Task.Supervisor, name: Marginalia.TaskSupervisor}`
6. `Marginalia.Cache`
7. `Marginalia.Runs`
8. (**main only**) `Marginalia.Mutterings.Clock` (placed after Runs)
9. `Marginalia.Recovery` (temporary, sweeps then ignores)
10. `MarginaliaWeb.Endpoint` (last)
`config_change/3` forwards to `MarginaliaWeb.Endpoint.config_change`.
**Periodic jobs**: only `Mutterings.Clock` (first tick 5 s after boot, then every 30 min). Cache expiry is lazy (5 min). Nothing cleans guests, tokens, orphan repos, or ETS.

### 12.2 `Repo` / `Marginalia`
`Marginalia.Repo` = `Ecto.Repo, otp_app :marginalia, adapter Ecto.Adapters.Postgres`; code uses `Repo.transact/1` (Ecto 3.13+). `Marginalia` module is empty.

### 12.3 `Marginalia.Release`
* `migrate()` : `Application.ensure_all_started(:ssl)`, load app, run all pending migrations up for each repo in `:ecto_repos`.
* `rollback(repo, version)` : migrate down to `version`.
* `make_admin(email)` : load app; `Repo.get_by(User, email: email)` (citext); nil -> prints `"no user with that email"`; else `is_admin := true` and prints `"#{email} is now an admin"`. Invoked as `bin/marginalia rpc 'Marginalia.Release.make_admin("you@example.com")'`. (Memory note: rpc-spawned processes die silently and rpc Logger output is invisible; long jobs on prod must use `Marginalia.TaskSupervisor` and a log file.)

### 12.4 Environment variables (every one read; `config/runtime.exs` runs in all envs unless noted)
| var | default | effect |
|---|---|---|
| `PHX_SERVER` | unset | if set (any value) endpoint `server: true` |
| `PORT` | `4000` | endpoint HTTP port in every env (runtime.exs runs after test.exs, so it overrides the 4002 set there; test has `server: false` anyway) |
| `LLM_PROVIDER` | `deepseek` | deploy-default provider; `openai` selects OpenAI, anything else DeepSeek |
| `OWNER_EMAIL` | `bobbbygrayson@gmail.com` | the one account allowed to switch backends, to publish folders, and whose links/cases are public |
| `DEEPSEEK_API_KEY`, `OPENAI_API_KEY` | nil | provider keys; **not read when `config_env == :test`** (test config pins them nil) |
| `LLM_MODEL` | nil | overrides the model for every call that does not name one (and `default_model/1`) |
| `LLM_FAST_MODEL` | nil | overrides `fast_model/1` |
| `DRAFT_REPO_ROOT` | unset | enables `Marginalia.Git`; directory holding one repo per draft slug |
| prod only: `DATABASE_URL` | **required** (raises) | Ecto URL |
| prod only: `ECTO_IPV6` | unset | `true` or `1` -> `socket_options: [:inet6]` |
| prod only: `POOL_SIZE` | `10` | Repo pool size |
| prod only: `SECRET_KEY_BASE` | **required** (raises) | cookie/signing secret |
| prod only: `PHX_HOST` | `example.com` | endpoint URL host (port 443, https) |
| prod only: `DNS_CLUSTER_QUERY` | nil | DNSCluster query |
| test only: `MIX_TEST_PARTITION` | `""` | suffix of the test DB name |
There is no GitHub token variable (tokens are per-request user input), no mail variable, and no variable for the user-agent.

### 12.5 Static config worth keeping
* Prod endpoint: IPv6 any-address bind, `force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["localhost","127.0.0.1"]]]` (HSTS), `cache_static_manifest`, logger level `:info`.
* Dev: DB `postgres/postgres@localhost/marginalia_dev`, pool 10. Test: DB `marginalia_test<partition>`, SQL sandbox, `pool_size = schedulers*2`, endpoint port 4002, `server: false`, bcrypt `log_rounds 1`, mailer `Swoosh.Adapters.Test`, `:llm_endpoints` pointing at `127.0.0.1:1`, `:llm_backoff_ms 0`, keys nil, (main) Clock `enabled: false`.
* Phoenix/LiveView/esbuild/tailwind settings are web-layer and omitted. `generators: [timestamp_type: :utc_datetime]`.

---

## 13. LLM call catalogue (provider, parameters, prompts)

Common: all use `Marginalia.LLM` (section 3). `max_tokens` below is what the **caller asks**; the wire value is `asked + 24000` (both providers). Timeout default 300 s. Retries only as in 3.2. No call here streams. "provider" is the caller-supplied override (owner's choice) or the deploy default; Cuts and Stacks pass none.

| # | caller | LLM fn | model | effort | temp | max_tokens | notes |
|---|---|---|---|---|---|---|---|
| 1 | `Links.Bulk.propose` | `call_tool` `propose_links` | `default_model(provider)` | high | 0.3 | 3000 | |
| 2 | `Links.Chat.ask` | `chat` | `default_model(provider)` | low | 0.5 | 4000 | no tools |
| 3 | `Cases.Chat.ask` | `chat` | `default_model(provider)` | low | 0.5 | 4000 | no tools |
| 4 | `Cuts.do_read` | `json` | `default_model()` | high | 0.3 | 8000 | `response_format json_object` |
| 5 | `Stacks.read_step` | `call_tool` `report_step` | `default_model()` | high | 0.2 | 3000 | |
| 6 | `Stacks.deepen_step` | `call_tool` `deepen_step` | `default_model()` | high | 0.2 | 3000 | |
| 7 | `Stacks.outline` | `call_tool` `outline_story` | `default_model()` | high | 0.4 | 6000 | |
| 8 | `Stacks.write_part` | `call_tool` `write_part` | `default_model()` | high | 0.4 | 4000 | |
| 9 | `Mutterings.ask` (main) | `chat` | `"deepseek-chat"` if provider is deepseek else `fast_model()` | none | 1.2 | `40*n + 100` | timeout 60 s |
| (10) | `Analysis.Linker` (out of scope) | `json` | `default_model(provider)` | high | 0.4 | 24000 | retried once with a "crowded" suffix on `:truncated` |
Calls 1 and 5-8 send `tools: [tool]`, `tool_choice: "auto"` (effort is not `none`) and expect `message.tool_calls[0].function.arguments` to be a JSON object. Totals: 9 call sites in scope, 8 distinct system prompts (calls 7 and 8 share one), 5 tool schemas (`propose_links`, `report_step`, `deepen_step`, `outline_story`, `write_part`). The longest fixed system prompt is the `Cases.Chat` one (13.3); the longest user message is a Stacks step or Cuts read (embeds up to 14000 characters of document, or the whole member texts).

### 13.1 Call 1 — `propose_links` (system prompt `@prompt` of `Links.Bulk`)
System:
```
You are given a list of documents that belong to one writer, one line each, and must choose which PAIRS are worth reading against each other in full.

The pass that follows is expensive and reads both documents' maps, so the list you return should be short. Two documents sharing a subject is not a reason. A specific part of one standing in a specific relation to a specific part of the other is.

Prefer pairs that are far apart in the list over adjacent ones: consecutive documents in a series are related by construction and the writer already knows it. What nobody can see unaided is the thing in document four that the thing in document ninety walks back.

Report by calling propose_links.
```
User: `"#{n} documents:\n\n#{listing}"` (listing from 5.2).
Tool:
```json
{"type":"function","function":{"name":"propose_links",
 "description":"Choose which pairs of these documents are worth reading against each other.",
 "parameters":{"type":"object","properties":{
  "pairs":{"type":"array","maxItems":24,
   "description":"The pairs worth the expensive pass, best first. Far fewer than every combination: a pair belongs here only if you expect a specific relation between specific parts, not because the two share a subject.",
   "items":{"type":"object","properties":{
     "a":{"type":"integer","description":"The number of the first document, from the list given."},
     "b":{"type":"integer","description":"The number of the second. Must differ from a."},
     "why":{"type":"string","description":"One sentence naming what you expect to find between them, concretely. \"Nine sets up the promise that fourteen pays off\", not \"both discuss the parser\". This is a hypothesis for the next pass to test, so it should be falsifiable."},
     "expect":{"type":"string","enum":["develops","pays_off","requires","tension","answers","echoes"],"description":"The relation you expect, from the kinds the linker can record. A guess; the pass that follows decides."}},
    "required":["a","b","why","expect"]}},
  "skipped":{"type":"string","description":"One sentence on what you deliberately left out and why. Empty if nothing stood out as a near miss."}},
  "required":["pairs","skipped"]}}}
```
Validation: 5.2 `validate`. Storage: none (result returned to the page; pairs later passed to `relate`).

### 13.2 Call 2 — `Links.Chat` system prompt
System message 1 (`@system`, verbatim):
```
You are reading two manuscripts that someone has related to each other, and answering
questions about the relationship.

You are given both maps — every beat, the spine, the threads, the open questions — and
every edge drawn between them, with the reason each was drawn. You do NOT have the full
text of either document. Do not pretend to.

HOW TO ANSWER
- Answer about the PAIR. "What does A say about X" is a question for the draft's own chat;
  here the interesting questions are what one document does to the other.
- Name the specific nodes and edges you are reasoning from. "They disagree about pacing"
  is useless; "A's §5 reading that the safety plan doubles as a moat sits against B's race
  to the top, and neither resolves who writes the rules" is the job.
- Quote only what you were given. Every beat arrives with the sentence it was anchored to;
  those are real and you may quote them. Anything else, you do not have — say so.
- An edge you were not given does not exist. If someone asks about a connection that is not
  in the list, say it was not drawn rather than inventing the reasoning for it.
- Be short. Three tight paragraphs beat a page.

WHAT YOU DO NOT DO
- You do not write prose for either manuscript.
- You do not rank them or say which is better.
- You do not soften a real disagreement into "both make good points".
```
System message 2 = `card(link)` (5.3). Then history, then optional cited card. Reply: `content` text, no JSON.

### 13.3 Call 3 — `Cases.Chat` system prompt
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
Then `card(reading)`, history, cited card (8).

### 13.4 Call 4 — `Cuts` read
System (`@system`):
```
You are given several members of one group — documents, or the readings of sub-groups — and nothing else. Say what they amount to together.

You have not been shown anything but what is below. Do not reach for context you do not have, and do not summarise the members back one at a time: the reader can already see them. Say what is true across them that no single member states.

Every piece of evidence must quote one of the members and name it by its number. A program checks each quote against that member's text and drops what it cannot find, so an approximate quote is a discarded claim.

An empty list is a real answer. If the members have nothing in common, say so in the thesis and return no threads.

Reply with one JSON object and nothing else.
```
User: 6.4. Expected reply JSON: `{"thesis": str, "threads": [{"claim": str, "evidence": [{"member": int, "quote": str}]}], "tensions": [same shape], "not_supported": str}`. Validation 6.5. Storage: `cuts` row (`thesis, threads, tensions, not_supported, dropped, content_sha, members, status`). Error: `:invalid_json`, `:truncated`, etc. -> `status failed`, `status_detail = inspect(reason)`; **no retry**.

### 13.5 Call 5 — `Stacks.read_step`
System (`@prompt`):
```
You read one document out of an ordered series that together build one thing, and report what it contributes to *building that thing* — not what happened to the project that produced it.

The reader you are writing for intends to build the same thing themselves, in this order, and has seen none of the other documents.

Quotes must be copied character for character. A program checks each one against the document and drops what it cannot find, so an approximate quote is a discarded field. Never write an excerpt yourself.

Report by calling report_step.
```
Tool `report_step`:
```json
{"type":"function","function":{"name":"report_step",
 "description":"Report what this document contributes to building the thing the series builds.",
 "parameters":{"type":"object","properties":{
  "capability":{"type":"string","description":"One line, present tense, naming what the thing can do after this document that it could not before. A property of the thing being built (\"a class becomes an actor\"), never an event (\"added actor support\")."},
  "requires":{"type":"array","items":{"type":"integer"},"description":"Numbers of earlier documents this one could not have been done without. Empty if it stands alone."},
  "lesson":{"type":"string","description":"Two or three sentences telling someone building this themselves what to do at this point. Imperative. No project history, no \"we\"."},
  "pitfall":{"type":"string","description":"The obvious approach that is wrong here and why, in one or two sentences. Empty string if the document does not say."},
  "pitfall_quote":{"type":"string","description":"The exact sentence from the document establishing the pitfall, copied character for character. Empty string if there is no pitfall."},
  "excerpts":{"type":"array","maxItems":2,"description":"Passages worth showing a learner. Quote a line that is already in the document; the passage around it is fetched for you. Never write one.",
   "items":{"type":"object","properties":{"quote":{"type":"string"},"caption":{"type":"string"}},"required":["quote","caption"]}}},
  "required":["capability","requires","lesson","pitfall","pitfall_quote","excerpts"]}}}
```
User: 7.2. Validation 7.2. Storage: `stack_steps` upsert. Failure: step skipped, error tuple collected; no retry.

### 13.6 Call 6 — `Stacks.deepen_step`
System (`@deep_prompt`):
```
You are reading one step of a series a second time, and this time you have the whole series in front of you — including everything that comes after it.

The first reading could not see forwards. It was told only what came before each step, which is the reading a learner follows, and it means nothing it said could account for what a later step changes. Your job is the part it could not do.

Do not restate the first reading. Say what only the whole chain reveals: how the thing actually works underneath, what must be got right here because something later leans on it, and whether a later step walks this back.

Quotes must be copied character for character. A program checks each one and drops what it cannot find.

Report by calling deepen_step.
```
Tool `deepen_step`:
```json
{"type":"function","function":{"name":"deepen_step",
 "description":"Report what can only be said about this step with the whole series in hand.",
 "parameters":{"type":"object","properties":{
  "mechanism":{"type":"string","description":"How this actually works, three or four sentences, below the level of what to do. Name the moving parts and how they fit. Concrete, from the document."},
  "watch_for":{"type":"string","description":"What to get right at this step because a later step leans on it, naming which. Empty string if nothing later depends on the details here."},
  "revised_by":{"type":"integer","description":"The number of a LATER step that corrects, replaces or materially changes what this one established. 0 if none does."},
  "revision":{"type":"string","description":"What that later step changes about this one, in one or two sentences. Empty string if nothing revises it."},
  "revision_quote":{"type":"string","description":"The exact sentence from the LATER step's own summary establishing the revision, copied character for character. Empty string if there is no revision."}},
  "required":["mechanism","watch_for","revised_by","revision","revision_quote"]}}}
```
User: 7.3. Validation `validate_deep`. Failure recorded on the step (7.3).

### 13.7 Calls 7 and 8 — compose (shared system prompt `@compose_prompt`)
System:
```
You are writing the long-form telling of how a thing gets built, from notes already checked line by line against the documents they came from. Your job is composition, not extraction: everything you need is in front of you, and anything not in front of you is something you do not know.

Write for someone about to build the same thing. They want the shape of the work and the order of it, and above all the places where the obvious move is wrong.

Lead with the load-bearing or surprising fact, never with "this guide will". Explain why the obvious version is wrong wherever the notes say so — that is usually the most valuable sentence available to you. Say plainly what is still undone. No marketing language, no bullet padding, no emoji.
```
Tool `outline_story`:
```json
{"type":"function","function":{"name":"outline_story",
 "description":"Divide the series into the parts the telling will be written in.",
 "parameters":{"type":"object","properties":{
  "title":{"type":"string","description":"A title for the whole telling. A claim, not a label."},
  "opening":{"type":"string","description":"Two or three paragraphs. What is being built, what makes it hard, and what the reader will have at the end. Lead with the load-bearing or surprising fact, never with \"this guide covers\"."},
  "closing":{"type":"string","description":"One or two paragraphs. What the reader has at the end, and what is honestly still undone."},
  "parts":{"type":"array","description":"The telling in parts, in the order the work is done. Every step must appear in exactly one part. Aim for parts of five to fifteen steps.",
   "items":{"type":"object","properties":{
     "heading":{"type":"string","description":"A claim, not a label."},
     "steps":{"type":"array","items":{"type":"integer"}}},
    "required":["heading","steps"]}}},
  "required":["title","opening","closing","parts"]}}}
```
Tool `write_part`:
```json
{"type":"function","function":{"name":"write_part",
 "description":"Write one part of the telling.",
 "parameters":{"type":"object","properties":{
  "prose":{"type":"string","description":"Three to six paragraphs telling this stretch as continuous prose. Say what gets built and in what order, and name the pitfalls where they bite. Do not enumerate the steps one by one — the reader already has that list."},
  "turn":{"type":"string","description":"The thing in this stretch a reader would not have guessed — a pitfall, or a place a later step walks an earlier one back. One or two sentences. Empty string if this stretch has none."}},
  "required":["prose","turn"]}}}
```
User messages: 7.4. Expected outline reply `{"title","opening","closing","parts":[{"heading","steps":[int]}]}`; write_part reply `{"prose","turn"}`. Validation `validate_story`. Storage `stack_stories`.

### 13.8 Call 9 — Mutterings (main)
System = `Mutterings.prompt()` (verbatim, including the typo "teh"):
```
You are Fyordor Dostoyevsky. You live in the modern day. You work a job at a grilled cheese sandwich factory in Menlo Park, CA. Give some words you might utter while working alone at teh sandwich counter. Keep it 240 characters or less.
```
User: `"Give #{n} of them. One per line. No numbering, no quotation marks, no introduction and no commentary: nothing but the words themselves."` Reply is plain `content`; parsed per section 10. Storage: `mutterings` rows.

### 13.9 What is *not* an LLM prompt here
`Cases`, `Kinship`, `Import`, `Git`, `Folders`, `Accounts` make no model calls. The Linker/Analysis/Document/Summary/Rewrite/Chat prompts live outside this scope.

---

## 14. Surprising or load-bearing behaviours to preserve (or consciously change)

* **S1 Redirects bypass the SSRF guard.** `Import.allowed` checks only the submitted URL; Req follows up to 3 redirects without re-checking, despite the module doc. IPv6-mapped IPv4 and `::` are not reserved.
* **S2 Name resolution is IPv4-only** and a name that does not resolve is refused as "private".
* **S3 `LLM.json` leaks a raw message** (`{:ok, message}`) when the reply message lacks a `"content"` key.
* **S4 `links.error` is `varchar(255)`** but is written with `inspect(reason)`, which can exceed 255 characters and then makes the status update fail (`{:ok, link} = ...` raises inside the Linker task).
* **S5 Cut reads are not recovered after a restart** (status stays `reading`); and a cut read dies with the socket.
* **S6 `Stacks.read_step` re-read overwrites deepening fields**; `deepen_stack` skips already-deepened steps unless `force`.
* **S7 `GitHub.with_commits/with_files` double-wrap errors** (`{:error, {:error, ...}}`) so the document text shows the inner tuple of the whole error.
* **S8 `to_draft` closing block** gets four newlines (`## Closing`, blank, blank, closing) because three elements are joined with `"\n\n"`.
* **S9 `store_edges` return value**: `dropped` excludes duplicates and over-cap items; non-map proposals are not counted at all.
* **S10 Bulk relate ignores Linker's outcome**: a pair whose link failed is still in `started`; crashed/timeout tasks vanish.
* **S11 `Import.Bulk.folder_for` and `GitHub.folder_for` pick by name across all parents** (`Repo.one` raises when two folders with that name exist under different parents).
* **S12 `Folders.delete_folder`** can raise on a sibling-name clash when lifting children.
* **S13 `Kinship` is dead code** in `lib/` (tests only); `Cases.Record` is read only by the case index page.
* **S14 `users_tokens` "login" (magic link) helpers are dead code**; `is_admin` has one reader; no guest/token cleanup exists; prod mail goes nowhere.
* **S15 DeepSeek `reasoning_headroom`**: every `max_tokens` on the wire is the caller's number plus 24000. A `:truncated` result therefore means the *answer* overflowed, not the thinking. Do not "fix" by lowering.
* **S16 Req defaults matter**: GitHub and page fetches are retried by Req (3 and 1 times respectively); the LLM POST is retried only by `LLM`'s own 3-attempt loop.
* **S17 Ecto behaviours to reproduce explicitly**: `unique_constraint` messages, whitespace-only strings cast to empty (so "can't be blank"), `citext` case-insensitive email equality, `Repo.insert(on_conflict: replace_all_except)` semantics, `ON DELETE` actions listed in section 1.

---
