# Marginalia test suite as acceptance criteria

Source: `test/` in the blimp-rewrite worktree (read-only). 1116 tests in 106 files. Two tests in `reading_test.exs` use the `test("...")` call form, so `grep -c 'test "'` gives 1114.

Split: 625 tests under `test/marginalia/` (pure functions and Ecto contexts), 491 under `test/marginalia_web/` (416 LiveView, 75 controller/plug/static/other). Recorded assertions (assert/refute/assert_* as written, loop bodies counted once): about 1341 under `test/marginalia/`, about 1130 under `test/marginalia_web/`.

Parts 1 to 9 below are the extraction: 1 pure functions, 2 imports/links/folders/summaries, 3 stacks/GitHub/git/decision graph/walkthrough, 4 reading/rewrite/revisions/runs/prompts/provider gate/quota/cache/accounts, 5 to 9 web. Each part ends with a `TOTALS` table that is the authoritative per-file count. Caveat: Part 8's own header says 115 tests; the real count for its 14 files is 105 (snap_view 6, stack_routes 3, stack_run 10, step_links 5, summary_vault 5, tour 7, login 5, registration 7, settings 12, walkthrough_live 9, work_tabs 7, work_trace 6, work_tree 15, work_upload_fallback 8). Where a part says "assertions", it is a static count by the extractor and can be off by a few.

## 0. How LLM calls are stubbed

They are not. There is no fake provider, no Req.Test, no Mox, no env flag that swaps a client. The seam is configuration, and tests stay hermetic by making every call fail at once:

- `config/test.exs`: `:deepseek_api_key` nil, `:openai_api_key` nil, `:llm_endpoints` = `%{deepseek_api_key: "http://127.0.0.1:1/chat/completions", openai_api_key: "http://127.0.0.1:1/v1/chat/completions"}` (port 1 refuses immediately), `:llm_backoff_ms` 0 (retries do not sleep).
- Tests for features gated on "a key exists" (chat composer, rewrite panel, confirm gate, walkthrough, inline thread) do `Application.put_env(:marginalia, :deepseek_api_key, "test-key")` and restore it in `on_exit`. No call succeeds. Tests of the no-key state set it to nil.
- Everything the model would have produced (nodes, edges, summaries, beats, tensions, stack results) is inserted straight into the DB, or validators are handed hand-written maps.
- Code paths that would call a model are exercised only up to an early return (empty body, `:not_read`, no nodes) or to the refused-connection failure.
- Other seams: `Application.put_env(:marginalia, :github_api, FakeHub)` (a fake module for GitHub, in import_flow_test); `:draft_repo_root` set to a tmp dir with the real `git` binary (git_test, async: false); `:owner_email` put_env (og, hooks, others).
- `:network` tests (4 in github_access_test) hit the live GitHub API and are excluded by `test_helper.exs` (`ExUnit.start(exclude: [:network])`). Run with `mix test --include network`.
- A rewrite offering the same seam needs: a configurable per-provider endpoint, a nil API key meaning "feature off", zero backoff in test, and a way to let detached tasks finish before teardown (see `drain_tasks` in section 2).

## 1. Files, test counts, subject

| file (under test/) | tests | test module |
|---|---|---|
| `marginalia_web/controllers/error_html_test.exs` | 3 | MarginaliaWeb.ErrorHTMLTest |
| `marginalia_web/controllers/error_json_test.exs` | 2 | MarginaliaWeb.ErrorJSONTest |
| `marginalia_web/controllers/user_session_controller_test.exs` | 6 | MarginaliaWeb.UserSessionControllerTest |
| `marginalia_web/error_page_test.exs` | 6 | MarginaliaWeb.ErrorPageTest |
| `marginalia_web/guest_upload_test.exs` | 13 | MarginaliaWeb.GuestUploadTest |
| `marginalia_web/hooks_test.exs` | 5 | MarginaliaWeb.HooksTest |
| `marginalia_web/live/applied_diff_test.exs` | 4 | MarginaliaWeb.AppliedDiffTest |
| `marginalia_web/live/case_index_test.exs` | 22 | MarginaliaWeb.CaseIndexTest |
| `marginalia_web/live/case_page_test.exs` | 8 | MarginaliaWeb.CasePageTest |
| `marginalia_web/live/case_read_test.exs` | 22 | MarginaliaWeb.CaseReadTest |
| `marginalia_web/live/cases_tour_test.exs` | 12 | MarginaliaWeb.CasesTourTest |
| `marginalia_web/live/changes_tab_test.exs` | 7 | MarginaliaWeb.ChangesTabTest |
| `marginalia_web/live/cluster_view_test.exs` | 4 | MarginaliaWeb.ClusterViewTest |
| `marginalia_web/live/confirm_gate_test.exs` | 6 | MarginaliaWeb.ConfirmGateTest |
| `marginalia_web/live/draft_render_test.exs` | 4 | MarginaliaWeb.DraftRenderTest |
| `marginalia_web/live/drawer_test.exs` | 10 | MarginaliaWeb.DrawerTest |
| `marginalia_web/live/import_flow_test.exs` | 25 | MarginaliaWeb.ImportFlowTest |
| `marginalia_web/live/inline_thread_test.exs` | 9 | MarginaliaWeb.InlineThreadTest |
| `marginalia_web/live/landing_features_test.exs` | 34 | MarginaliaWeb.LandingFeaturesTest |
| `marginalia_web/live/landing_live_test.exs` | 14 | MarginaliaWeb.LandingLiveTest |
| `marginalia_web/live/link_chat_flow_test.exs` | 15 | MarginaliaWeb.LinkChatFlowTest |
| `marginalia_web/live/link_flow_test.exs` | 16 | MarginaliaWeb.LinkFlowTest |
| `marginalia_web/live/link_index_test.exs` | 7 | MarginaliaWeb.LinkIndexTest |
| `marginalia_web/live/link_tag_menu_test.exs` | 4 | MarginaliaWeb.LinkTagMenuTest |
| `marginalia_web/live/linked_index_test.exs` | 5 | MarginaliaWeb.LinkedIndexTest |
| `marginalia_web/live/links_index_scroll_test.exs` | 6 | MarginaliaWeb.LinksIndexScrollTest |
| `marginalia_web/live/live_beats_test.exs` | 4 | MarginaliaWeb.LiveBeatsTest |
| `marginalia_web/live/note_deck_test.exs` | 5 | MarginaliaWeb.NoteDeckTest |
| `marginalia_web/live/note_piles_test.exs` | 7 | MarginaliaWeb.NotePilesTest |
| `marginalia_web/live/progress_test.exs` | 4 | MarginaliaWeb.ProgressTest |
| `marginalia_web/live/public_changes_test.exs` | 6 | MarginaliaWeb.PublicChangesTest |
| `marginalia_web/live/public_drafts_test.exs` | 7 | MarginaliaWeb.PublicDraftsTest |
| `marginalia_web/live/public_linked_test.exs` | 5 | MarginaliaWeb.PublicLinkedTest |
| `marginalia_web/live/public_reading_test.exs` | 13 | MarginaliaWeb.PublicReadingTest |
| `marginalia_web/live/read_changes_test.exs` | 5 | MarginaliaWeb.ReadChangesTest |
| `marginalia_web/live/read_view_test.exs` | 7 | MarginaliaWeb.ReadViewTest |
| `marginalia_web/live/reading_owner_test.exs` | 5 | MarginaliaWeb.ReadingOwnerTest |
| `marginalia_web/live/rewrite_apply_test.exs` | 1 | MarginaliaWeb.RewriteApplyTest |
| `marginalia_web/live/rewrite_panel_test.exs` | 8 | MarginaliaWeb.RewritePanelTest |
| `marginalia_web/live/snap_view_test.exs` | 6 | MarginaliaWeb.SnapViewTest |
| `marginalia_web/live/stack_routes_test.exs` | 3 | MarginaliaWeb.StackRoutesTest |
| `marginalia_web/live/stack_run_test.exs` | 10 | MarginaliaWeb.StackRunTest |
| `marginalia_web/live/step_links_test.exs` | 5 | MarginaliaWeb.StepLinksTest |
| `marginalia_web/live/summary_vault_test.exs` | 5 | MarginaliaWeb.SummaryVaultTest |
| `marginalia_web/live/tour_test.exs` | 7 | MarginaliaWeb.TourTest |
| `marginalia_web/live/user_live/login_test.exs` | 5 | MarginaliaWeb.UserLive.LoginTest |
| `marginalia_web/live/user_live/registration_test.exs` | 7 | MarginaliaWeb.UserLive.RegistrationTest |
| `marginalia_web/live/user_live/settings_test.exs` | 12 | MarginaliaWeb.UserLive.SettingsTest |
| `marginalia_web/live/walkthrough_live_test.exs` | 9 | MarginaliaWeb.WalkthroughLiveTest |
| `marginalia_web/live/work_tabs_test.exs` | 7 | MarginaliaWeb.WorkTabsTest |
| `marginalia_web/live/work_trace_test.exs` | 6 | MarginaliaWeb.WorkTraceTest |
| `marginalia_web/live/work_tree_test.exs` | 15 | MarginaliaWeb.WorkTreeTest |
| `marginalia_web/live/work_upload_fallback_test.exs` | 8 | MarginaliaWeb.WorkUploadFallbackTest |
| `marginalia_web/og_test.exs` | 6 | MarginaliaWeb.OgTest |
| `marginalia_web/sitemap_test.exs` | 6 | MarginaliaWeb.SitemapTest |
| `marginalia_web/user_auth_test.exs` | 28 | MarginaliaWeb.UserAuthTest |
| `marginalia/accounts_test.exs` | 33 | Marginalia.AccountsTest |
| `marginalia/anchor_test.exs` | 11 | Marginalia.Analysis.AnchorTest |
| `marginalia/apply_rewrite_test.exs` | 5 | Marginalia.ApplyRewriteTest |
| `marginalia/beat_density_test.exs` | 5 | Marginalia.BeatDensityTest |
| `marginalia/bulk_links_test.exs` | 14 | Marginalia.BulkLinksTest |
| `marginalia/cache_test.exs` | 7 | Marginalia.CacheTest |
| `marginalia/chat_modes_test.exs` | 7 | Marginalia.ChatModesTest |
| `marginalia/clusters_test.exs` | 6 | Marginalia.ClustersTest |
| `marginalia/compare_summary_test.exs` | 6 | Marginalia.CompareSummaryTest |
| `marginalia/cuts_test.exs` | 19 | Marginalia.CutsTest |
| `marginalia/decision_graph_test.exs` | 24 | Marginalia.Analysis.DecisionGraphTest |
| `marginalia/diff_test.exs` | 10 | Marginalia.DiffTest |
| `marginalia/document_test.exs` | 8 | Marginalia.DocumentTest |
| `marginalia/editing_test.exs` | 8 | Marginalia.EditingTest |
| `marginalia/editor_tools_test.exs` | 8 | Marginalia.Chat.EditorToolsTest |
| `marginalia/effort_test.exs` | 2 | Marginalia.EffortTest |
| `marginalia/folders_test.exs` | 17 | Marginalia.FoldersTest |
| `marginalia/git_test.exs` | 9 | Marginalia.GitTest |
| `marginalia/github_access_test.exs` | 15 | Marginalia.GitHubAccessTest |
| `marginalia/github_document_test.exs` | 16 | Marginalia.GitHubDocumentTest |
| `marginalia/github_stack_test.exs` | 9 | Marginalia.GitHubStackTest |
| `marginalia/import_bulk_test.exs` | 15 | Marginalia.ImportBulkTest |
| `marginalia/import_query_test.exs` | 31 | Marginalia.ImportQueryTest |
| `marginalia/import_test.exs` | 13 | Marginalia.ImportTest |
| `marginalia/kinship_test.exs` | 8 | Marginalia.Cases.KinshipTest |
| `marginalia/link_chat_test.exs` | 5 | Marginalia.LinkChatTest |
| `marginalia/links_test.exs` | 24 | Marginalia.LinksTest |
| `marginalia/markdown_test.exs` | 2 | Marginalia.MarkdownTest |
| `marginalia/outline_test.exs` | 5 | Marginalia.OutlineTest |
| `marginalia/prompts_test.exs` | 7 | Marginalia.PromptsTest |
| `marginalia/provider_gate_test.exs` | 20 | Marginalia.ProviderGateTest |
| `marginalia/quota_test.exs` | 7 | Marginalia.QuotaTest |
| `marginalia/reading_render_test.exs` | 6 | Marginalia.ReadingRenderTest |
| `marginalia/reading_test.exs` | 16 | Marginalia.ReadingTest |
| `marginalia/recovery_test.exs` | 4 | Marginalia.RecoveryTest |
| `marginalia/reflow_test.exs` | 12 | Marginalia.Works.ReflowTest |
| `marginalia/revisions_test.exs` | 11 | Marginalia.RevisionsTest |
| `marginalia/rewrite_test.exs` | 30 | Marginalia.RewriteTest |
| `marginalia/runs_test.exs` | 9 | Marginalia.RunsTest |
| `marginalia/segmenter_test.exs` | 13 | Marginalia.Works.SegmenterTest |
| `marginalia/selection_test.exs` | 16 | Marginalia.SelectionTest |
| `marginalia/sentences_test.exs` | 28 | Marginalia.Works.SentencesTest |
| `marginalia/sentences_works_test.exs` | 11 | Marginalia.SentencesWorksTest |
| `marginalia/stack_leak_test.exs` | 9 | Marginalia.StackLeakTest |
| `marginalia/stack_to_draft_test.exs` | 6 | Marginalia.StackToDraftTest |
| `marginalia/stacks_test.exs` | 26 | Marginalia.StacksTest |
| `marginalia/summaries_to_draft_test.exs` | 7 | Marginalia.SummariesToDraftTest |
| `marginalia/summarise_folder_test.exs` | 11 | Marginalia.SummariseFolderTest |
| `marginalia/summary_test.exs` | 19 | Marginalia.SummaryTest |
| `marginalia/walkthrough_test.exs` | 13 | Marginalia.WalkthroughTest |

## 2. Support (`test/support/`, `test/test_helper.exs`)

There are no work, folder, link or section fixtures. Only users. Every test builds its own data inline; each test's setup is recorded in its section below.

- `test_helper.exs`: `ExUnit.start(exclude: [:network])`; `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, :manual)`.
- `Marginalia.DataCase`: sandbox via `start_owner!(Repo, shared: not tags[:async])`. On exit it calls `drain_tasks/1` before stopping the owner. `drain_tasks(timeout \\ 2000)` polls `Task.Supervisor.children(Marginalia.TaskSupervisor)` until empty twice in a row (25 ms apart) and returns `:timeout` rather than failing. Reason in the source: a read and a link pass are fire-and-forget (the LiveView answers the socket immediately); the test finished, its sandbox owner exited, and the task still held the connection, giving a `DBConnection.ConnectionError` blamed on an unrelated test, about one run in five. A read spawns a supervised task that runs an async_stream whose children belong to the task, hence "empty twice". `errors_on(changeset)` interpolates `%{key}` in messages via `traverse_errors`.
- `MarginaliaWeb.ConnCase`: `@endpoint MarginaliaWeb.Endpoint`, sandbox as above, context `conn: build_conn()`. `register_and_log_in_user/1` creates `user_fixture()` and its `Scope.for_user`, then logs in: `generate_user_session_token(user)`, `init_test_session(%{})`, `put_session(:user_token, token)`; the `:token_authenticated_at` tag overrides the token's authenticated_at. Returns `%{conn, user, scope}`.
- `Marginalia.AccountsFixtures`:
  - `unique_user_email/0` = `"user#{System.unique_integer()}@example.com"`.
  - `valid_user_password/0` = `"hello world!"`.
  - `valid_user_attributes/1` = `%{email: unique, password: "hello world!"}` merged with attrs.
  - `user_fixture/1` = `Accounts.register_user(attrs)`; registration confirms immediately, so the user is confirmed.
  - `unconfirmed_user_fixture/1` = a user whose `confirmed_at` is set to nil afterwards (the confirmation API still exists in `Accounts` and has tests).
  - `user_scope_fixture/0,1`, `set_password/1` (via `update_user_password`), `extract_user_token/1` (captures the email text body between `[TOKEN]` markers), `override_token_authenticated_at/2`, `generate_user_magic_link_token/1` (builds a "login" email token and inserts it), `offset_user_token/3` (shifts inserted_at and authenticated_at).
  - `owner_fixture/0`: a user whose email is changed to `Application.get_env(:marginalia, :owner_email)`. Trace and Prompts pages are owner-only. `:owner_email` comes from `config/runtime.exs` (default `bobbbygrayson@gmail.com`) and is not overridden in `config/test.exs`; several tests put_env `"owner@example.com"` instead.
- Seed data for the rewrite: a default user has a unique `userN@example.com` address and password `hello world!`; nothing else exists until a test creates it.

## 3. Cross-cutting observations (from the extractors; each file's "Behavior not obvious" bullets have the detail)

- Structural tests that read Elixir source or assets and need a Blimp equivalent or must be dropped: `hooks_test` (regex-scans `lib/marginalia_web/**/*.ex` for colocated JS hooks and selectors; requires `components/link_chat.ex` to define a `.Composer` hook), `landing_features_test` (reads `landing_live.ex`, `chat/editor.ex`, `analysis/linker.ex`, `import/query.ex`; uses `Phoenix.Router.route_info`), `link_chat_flow_test` (reads `assets/css/app.css`), `link_flow_test` (asserts `MarginaliaWeb.LinkLive.Show` is absent), `effort_test` (reads lib source and greps the `effort:` setting at each LLM call site), `prompts_test` (one test reads `summary.ex` and `document.ex`; the `document.ex` loop never runs because no `@prompt` heredoc matches).
- Static asset checks: `sitemap_test` and `og_test` read `priv/static/robots.txt` and `og-cases.png` (must be 2400x1260). `cluster_view_test` has an `@tag :screenshot` test with no assertions; it runs by default, reads `priv/static/assets/css/app.css` (absent until assets are built, so it raises) and writes `/tmp/cluster.html`.
- Prompt text is asserted literally (`prompts_test`): "never assume anyone's gender", "They set June 2020 as the baseline", "Never a bare" in the linker prompt. The rewrite must carry equivalent prompt strings.
- Weak or vacuous tests, so a pass is not evidence: the `choices/0` test (both keys nil, returns `[]`); "only the whole-draft passes ask for high effort" checks only three pass ids; "pinned threads stay out of the drawer's strip" (vacuous on empty lists); "asking shows the question and that it is thinking" asserts only the question; `assert work.id` and `assert b_node.id` are no-ops in Part 2; `confirm_gate` "pressing it starts the read" accepts status "reading", "failed" or "read"; `draft_render_test`'s "'we hold that' is preferred over a bare 'accordingly'" actually checks "We conclude that" beating "Accordingly,"; the user_auth_test `on_mount :require_authenticated` failure tests are named "redirects" but check only `:halt` and a nil scope.
- Timing and nondeterminism: `linked_index_test` asserts `public_links` finishes under 500 ms; `Process.sleep(1_400)` and a 200 ms `refute_receive` appear in Part 8; `work_trace_test` "start_read" retry relies on the refusing endpoint and has a possible race on its empty-nodes assertion; `progress_test` is `async: true` with no shared sandbox; `note_deck_test` has a comment saying three beats carry a connection but creates four edges.
- Environment dependencies: `import_test` calls `Import.allowed` against real public hosts and expects `localhost.localdomain` refused (may need DNS); `git_test` needs a real `git` binary; `decision_graph_test` calls private `DG.execute/2` via `:erlang.apply`; `stack_leak_test` uses a leak string containing fullwidth pipes U+FF5C.
- `effort_test` has 2 `test` calls but 6 at runtime (1 named plus 5 generated from a template); `selection_test` has 11 "constructs" tests written as bullets, not headings; `note_piles_test` is a pure-function file inside the web tree (`WorkLive.Show.piles/1`).
- `rewrite_panel_test` and `links_index_scroll_test` sections contain page text the extractor inferred from `lib/` rather than read in the test; those lines are marked "inferred".


# PART 1. Pure functions

# Part A: pure-function and small-context tests

Notation: Elixir string literals are quoted as in source. `\n`, `\t`, `\r\n` are real characters. `<>` is concatenation in the source; the resulting string is what matters. All files in this part are `async: true` unless stated.

## test/marginalia/segmenter_test.exs  (13 tests; covers Marginalia.Works.Segmenter.split/1)

Module `Marginalia.Works.SegmenterTest`, `use ExUnit.Case, async: true`, alias `Marginalia.Works.Segmenter`. No DB, no stubs. `Segmenter.split(text)` returns a list of maps with at least `:title` and `:body`. Local helper `word_count(text)` = `length(String.split(text, ~r/\s+/, trim: true))`.

### test "a blog post with no structure is one section"
Input: `Enum.map_join(1..4, "\n\n", fn i -> "Paragraph #{i}. " <> String.duplicate("word ", 40) end)` (4 paragraphs of 40 words, no headings).
- assert `[%{body: body}] = Segmenter.split(text)` (exactly one section)
- assert body =~ "Paragraph 1"
- assert body =~ "Paragraph 4"
(3 assertions)

### test "markdown headings win when the writer supplied them"
Input heredoc (each body line is the word followed by a space, repeated 300 times):
```
# The Opening
<"alpha " x300>

# The Middle
<"beta " x300>

# The End
<"gamma " x300>
```
(heredoc ends with a newline after the last gamma line.)
- assert length(sections) == 3
- assert Enum.map(sections, & &1.title) == ["The Opening", "The Middle", "The End"]
- assert hd(sections).body =~ "alpha"
(3)

### test "chapter markers are found when there is no markdown"
Input heredoc:
```
Chapter 1
<"one " x300>

Chapter 2
<"two " x300>
```
- assert length(sections) == 2
- assert Enum.at(sections, 0).title =~ "Chapter 1"
(2)

### test "prose before the first marker is kept, not dropped"
Input heredoc: `"prologue " x300`, blank line, `Chapter 1`, `"one " x300`, blank line, `Chapter 2`, `"two " x300`.
- assert Enum.any?(sections, &(&1.body =~ "prologue"))
(1)

### test "a long unstructured draft is packed into multiple sections without splitting paragraphs"
`para = String.duplicate("word ", 300)`; `text = Enum.map_join(1..12, "\n\n", fn i -> "P#{i} " <> para end)` (12 paragraphs of 300 words, no headings).
- assert length(sections) > 1
- comment: "every paragraph survives intact somewhere"
- `for i <- 1..12`: assert Enum.any?(sections, &String.contains?(&1.body, "P#{i} ")) (one assert statement executed 12 times)
(2 static)

### test "runt trailing sections are folded rather than left as stubs"
Input heredoc:
```
# Big
<"alpha " x400>

# Tiny
two words
```
- assert length(sections) == 1  (Tiny is folded into Big)
- assert hd(sections).body =~ "two words"
(2)

### describe "oversized sections"
Comment above the first test: "An oral argument transcript is the real case: "# Case" and "## Rebuttal" is two headings and twelve thousand words, which used to come back as one section no model reads closely."

#### test "a heading section far over target is windowed into parts"  (describe "oversized sections")
`para = String.duplicate("alpha ", 300) <> "\n\n"` (300 words, then a blank line). Input heredoc:
```
# Argument
<para x20>
## Rebuttal
<"omega " x300>
```
(about 6000 words under Argument; the heredoc supplies one more newline before `## Rebuttal`.)
- assert length(sections) > 2
- assert Enum.all?(sections, &(word_count(&1.body) <= 4_000))
- assert Enum.any?(sections, &(&1.title =~ ~r/^Argument \(1\/\d+\)$/))
- assert Enum.any?(sections, &(&1.title == "Rebuttal"))
(4)

#### test "parts keep every word, in order, and never split a paragraph"  (describe "oversized sections")
`paras = for i <- 1..30, do: "p#{i} " <> String.duplicate("word ", 200)`; `text = "# Whole\n\n" <> Enum.join(paras, "\n\n")` (about 6000 words under one heading). `rejoined = Enum.map_join(sections, "\n\n", & &1.body)`.
For each `{p, i}` of `Enum.with_index(paras, 1)`:
- assert String.contains?(rejoined, "p#{i} "), message "lost paragraph #{i}"
- assert Enum.any?(sections, &String.contains?(&1.body, String.trim(p))), message "paragraph #{i} was split across sections"
(2 static, 60 executed). The second check requires each whole trimmed paragraph to appear contiguously inside one section body.

#### test "one enormous paragraph is left whole rather than cut mid-sentence"  (describe "oversized sections")
`text = "# Wall\n\n" <> String.duplicate("word ", 6_000)`
- assert `[only] = Segmenter.split(text)` (exactly one section)
- assert word_count(only.body) >= 6_000
(2)

### test "a derived title carries no markdown syntax"
Comment: "A derived title goes into a contents list and a minimap, neither of which renders markdown; the asterisks were showing up in both."
Input: `"**JUSTICE GORSUCH:** Counsel, what is the limiting principle here?\n\n" <> String.duplicate("word ", 400)`
- assert `[only] = Segmenter.split(text)`
- assert only.title =~ "JUSTICE GORSUCH: Counsel"
- refute only.title =~ "*"
(3)

### test "a lone markdown heading does not become part of the title"
Input: `"# Chatrie v. United States — Argument\n\n" <> String.duplicate("word ", 400)` (em dash U+2014)
- assert `[only] = Segmenter.split(text)`
- refute only.title =~ "#"
- assert only.title =~ "Chatrie v. United States"
(3)

### test "empty input yields nothing"
(Defined after `defp word_count`.)
- assert Segmenter.split("") == []
- assert Segmenter.split("   \n\n  ") == []
- assert Segmenter.split(nil) == []
(3)

### test "prose arrives one sentence per line, paragraphs intact, code untouched"
Input:
```elixir
"First sentence of the opening. Second one,\nwrapped by an editor. Third.\n\n" <>
  "```\nx = 1. y = 2.\n```\n\n" <> "Last paragraph. Done."
```
- assert `[%{body: body}] = Segmenter.split(text)` (one section)
- assert body ==
```elixir
"First sentence of the opening.\nSecond one, wrapped by an editor.\nThird.\n\n" <>
  "```\nx = 1. y = 2.\n```\n\n" <> "Last paragraph.\nDone."
```
(2)

Behavior not obvious from the code:
- Segmentation precedence as tested: markdown headings first, then "Chapter N" lines, then unstructured text packed into multiple sections at paragraph boundaries.
- Runt sections (here "two words") are folded into a neighbouring section, not emitted.
- A heading section far over target is windowed into parts titled with the regex `^Argument \(1\/\d+\)$` (title + " (i/n)"); no part body exceeds 4,000 words; the next heading keeps its plain title ("Rebuttal").
- A single paragraph larger than the window is never cut ("left whole rather than cut mid-sentence"), even at 6000 words.
- Derived titles (no heading) are stripped of markdown (`**`), and a lone `# ` heading is not part of the title.
- Section bodies come out already in one-sentence-per-line form (Sentences.reflow rule), fenced code untouched, wrapped lines joined.
- Non-ASCII (em dash) must survive in text.

Assertion count: 32 (static).

---

## test/marginalia/sentences_test.exs  (28 tests; covers Marginalia.Works.Sentences.reflow/1)

Module `Marginalia.Works.SentencesTest`, `async: true`. Moduledoc: "Prose is stored one sentence per line. The property worth asserting is the one the diff view and every outside diff rests on: the only line breaks inside a paragraph are sentence ends, and blocks that are not prose are byte for byte what they were." All tests call `Sentences.reflow/1` (string or nil -> string or nil). No stubs.

### test "a hard-wrapped paragraph comes back one sentence per line"
Input:
```elixir
"At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\n" <>
  "reset for lock delay. The idea came from agent-8, which had not committed the\n" <>
  "code. Agent-8 had logged a decision."
```
Expected:
```elixir
"At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step reset for lock delay.\n" <>
  "The idea came from agent-8, which had not committed the code.\n" <>
  "Agent-8 had logged a decision."
```
(1 assertion)

### test "paragraphs stay separated by a blank line"
- "One. Two.\n\nThree. Four." -> "One.\nTwo.\n\nThree.\nFour."

### test "reflowing twice changes nothing"
`once = Sentences.reflow("She stood at the window\nfor an hour. The kettle went cold. It was late.")`
- assert Sentences.reflow(once) == once

### test "abbreviations and initials do not end a sentence"
- "Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done." -> "Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone."

### test "a period followed by a lowercase word is not a boundary"
- "The file is game.js and it runs. agent-8 logged it. Then it ran." -> "The file is game.js and it runs. agent-8 logged it.\nThen it ran."  (no break after "runs." because next word is lowercase "agent-8"; break after "it." because "Then" is capitalised)

### test "decimals, question marks, exclamations and closing quotes"
Input (`~s(...)`, quotes literal): `It scored 3.16 on the board! Was that enough? "No," she said. "Not nearly." Fine.`
Expected: `It scored 3.16 on the board!\nWas that enough?\n"No," she said.\n"Not nearly."\nFine.`

### test "fenced code is untouched, blank lines and all"
`code = "```\nfoo. Bar baz.\n\nqux. Quux.\n```"`
- "Intro one. Intro two.\n\n" <> code -> "Intro one.\nIntro two.\n\n" <> code

### test "headings, tables, lists, indented code and rules are untouched"
Blocks; for each, `assert(Sentences.reflow(b) == b)` (one assert in a `for`, 6 executions):
1. "## A heading. With a period. And More."
2. "| a. B | c. D |\n|---|---|\n| e. F | g. H |"
3. "- one. Two.\n- three. Four."
4. "1. first. Second.\n2. third. Fourth."
5. "    code. More code.\n    still code. Yes."  (four-space indented)
6. "---"
(1 static assertion)

### test "a blockquote is reflowed and keeps its prefix"
Input: "> agent-8 logged that the cap locks a piece. Agent-7 read it. It\n> wrote its own version."
Expected: "> agent-8 logged that the cap locks a piece.\n> Agent-7 read it.\n> It wrote its own version."

### test "html blocks are untouched"
`html = "<div class=\"x\">one. Two.\nthree.</div>"`; assert reflow(html) == html

### test "markdown emphasis at the start of a sentence still starts one"
Input: "This is bold. **Really** bold. `Code` too. `code` is not a start."
Expected: "This is bold.\n**Really** bold.\n`Code` too. `code` is not a start."
(`**Really**` and backtick-capitalised `Code` start a sentence; backtick-lowercase `code` does not)

### test "curly quotes, parentheses and brackets close a sentence"
(under comment header `# --- edges of the boundary rule ---`)
Input (`~s|...|`): `He said “stop.” Then he left (for good.) Fine [really.] Done.`
Expected: `He said “stop.”\nThen he left (for good.)\nFine [really.]\nDone.`

### test "an ellipsis ends a sentence only when a sentence follows"
- "Wait... What? Wait... and then. End." -> "Wait...\nWhat?\nWait... and then.\nEnd."

### test "a sentence can start with a digit, a link or an opening quote"
Input (`~s|...|`): `It was late. 2026 was the year. [Deciduous](https://deciduous.dev) records it. "Yes," she said.`
Expected: `It was late.\n2026 was the year.\n[Deciduous](https://deciduous.dev) records it.\n"Yes," she said.`

### test "capitals outside ASCII start sentences too"
- "Élan vital. Über alles. Ça va." -> "Élan vital.\nÜber alles.\nÇa va."

### test "more abbreviations that are not sentence ends"
- "See Fig. 3 and cf. the table. Mrs. Smith vs. Mr. Jones, Inc. won. Prof. Lee agreed." -> "See Fig. 3 and cf. the table.\nMrs. Smith vs. Mr. Jones, Inc. won.\nProf. Lee agreed."

### test "a one-sentence paragraph is one line"
- "A single sentence, wrapped\nby an editor at seventy\ncolumns, is one line" -> "A single sentence, wrapped by an editor at seventy columns, is one line"

### test "runs of spaces, tabs and ragged indentation collapse to one space"
- "One   sentence,\t\tspaced.\n   Another,\n\t indented. " -> "One sentence, spaced.\nAnother, indented."  (trailing space dropped)

### test "windows line endings are absorbed"
- "One. Two\r\nthree.\r\n\r\nFour." -> "One.\nTwo three.\n\nFour."

### test "a period inside a word or a version number is not a boundary"
- "Use v1.2 of game.js today. Elixir 1.19.5 works. Done." -> "Use v1.2 of game.js today.\nElixir 1.19.5 works.\nDone."

### test "a blockquote keeps its own paragraph breaks"
(under comment header `# --- blocks that must come back untouched, or nearly ---`)
- "> First. Second.\n>\n> Third. Fourth." -> "> First.\n> Second.\n>\n> Third.\n> Fourth."

### test "a setext heading is not joined to its underline"
- assert Sentences.reflow("A title. With a period.\n=====") == "A title. With a period.\n====="
- assert Sentences.reflow("Sub. Title.\n---") == "Sub. Title.\n---"
(2)

### test "a table with no leading pipes is untouched"
`t = "a. B | c. D\n---|---\ne. F | g. H"`; assert reflow(t) == t

### test "a fenced block with a tilde fence and an info string is untouched"
`code = "~~~elixir\nx = 1. y = 2.\n\nz. Z.\n~~~"`; assert reflow(code) == code

### test "an image or link on a line of its own is untouched"
- "![alt text. More.](img.png)" -> same string

### test "nothing, nil and whitespace come back as nothing"
- assert Sentences.reflow(nil) == nil
- assert Sentences.reflow("") == ""
- assert Sentences.reflow("   \n\n  ") == ""
(3)

### test "a mixed document: only the prose moves"
Input:
```elixir
"# Title\n\nIntro one. Intro two.\n\n- item one. Still one.\n- item two.\n\n" <>
  "```\ncode. Code.\n```\n\n> Quoted one. Quoted two.\n\nOutro one. Outro\ntwo."
```
Expected:
```elixir
"# Title\n\nIntro one.\nIntro two.\n\n- item one. Still one.\n- item two.\n\n" <>
  "```\ncode. Code.\n```\n\n> Quoted one.\n> Quoted two.\n\nOutro one.\nOutro two."
```

### test "reflowing the mixed document twice changes nothing"
`doc = "Intro one. Intro two.\n\n- item one.\n\n> Quoted one. Quoted two.\n\nOutro."`; `once = Sentences.reflow(doc)`; assert reflow(once) == once

Behavior not obvious from the code:
- Non-prose blocks (ATX and setext headings, tables with or without leading pipes, list blocks, indented code, rules, HTML blocks, ``` and ~~~ fenced code, standalone image/link lines) come back byte for byte; list items are not split even with several sentences.
- Boundary rule as tested: terminal . ! ? (optionally followed by closing quote/paren/bracket, incl. curly quotes) + whitespace + a sentence start (uppercase incl. non-ASCII, digit, opening quote, `[link`, `**Emph`, backticked capital). A lowercase next word is not a boundary. Dr., e.g., cf., No., Fig., Mrs., Mr., vs., Inc., Prof. and single-letter initials do not end a sentence. Digits-inside decimals/versions/filenames (3.16, v1.2, game.js, 1.19.5) do not.
- "..." followed by a capital is a boundary; followed by a lowercase word is not.
- Idempotent.
- Blockquote lines keep `> `; a bare `>` line is a paragraph break inside the quote and is preserved.
- CRLF normalised to LF; spaces/tabs collapse; leading/trailing spaces on lines dropped.
- nil -> nil; blank/whitespace-only string -> "".

Assertion count: 31 (static).

---

## test/marginalia/sentences_works_test.exs  (11 tests; covers one-sentence-per-line storage through Works.create_work, Works.replace_block, Reading.page, Diff, Anchor.verify)

Module `Marginalia.SentencesWorksTest`, `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Diff, Reading, Works}` and `Marginalia.Analysis.Anchor`. Moduledoc: "One sentence per line, seen from the draft's point of view. The splitter is tested on its own. What matters here is what the form does to everything built on a draft: the baseline, the anchors, the edits, the diff and the page. The property to hold on to is that none of them can tell the difference, except the diff, which gets better."

Module attribute `@wrapped` (heredoc; ends with newline):
```
# A draft

She had been standing at the window for an hour
before anyone noticed. The kettle went cold on
the counter. Nobody moved to fill it again.

By evening the argument had found its real
subject, which was not the kettle. It was the
window.
```

Shared `setup` (every test):
```elixir
user = user_fixture()
{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => @wrapped})
%{user: user, work: work, section: hd(Works.list_sections(work.id))}
```
`user_fixture()` with no args (test/support/fixtures/accounts_fixtures.ex). `Works.create_work/2` takes `(user_id, %{"title", "body"})` with string keys and returns `{:ok, work}`. No folder, no LLM, no stubs.

### test "a hard-wrapped upload is stored one sentence per line"  (context: `%{section: s}`)
Comment: "one heading is not enough for the segmenter to cut on, so it stays in the body"
- assert s.body ==
```elixir
"# A draft\n\n" <>
  "She had been standing at the window for an hour before anyone noticed.\n" <>
  "The kettle went cold on the counter.\n" <>
  "Nobody moved to fill it again.\n\n" <>
  "By evening the argument had found its real subject, which was not the kettle.\n" <>
  "It was the window."
```
(1; no trailing newline; the work has one section whose `body` includes the `# A draft` heading line.)

### test "the baseline is the reflowed body, so the replay starts from what is stored"  (`%{work: work}`)
- assert work.baseline_body == work.body
- assert work.body =~ "before anyone noticed.\nThe kettle"
(2)

### test "reflowing does not change the word count"  (`%{work: work}`)
- assert work.word_count == length(String.split(@wrapped, ~r/\s+/, trim: true))   (words counted on the original wrapped text, so "#" counts as a word)
(1)

### test "a windowed draft's title is its first sentence, not a wrapped fragment"  (`%{user: user}`)
Comment: "wrapped after two words: as it arrived, the first line was too short to be a title"
```elixir
body =
  "The opening\nsentence is the title of this section, whole. Then more. " <>
    String.duplicate("word ", 40)

{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
[s] = Works.list_sections(work.id)
```
- assert s.title =~ "The opening sentence is the title"
- refute s.title == "Section 1"
(2)

### test "a quote spanning two sentences verifies against the stored text and keeps the newline"  (`%{section: s}`)
```elixir
flat = "went cold on the counter. Nobody moved"
```
- assert {:ok, span} = Anchor.verify(flat, s.body)   (Anchor.verify/2: quote, text)
- assert span == "went cold on the counter.\nNobody moved"
(2)

### test "a note anchored across a sentence break lands on its paragraph"  (`%{work: work, section: s}`)
```elixir
{:ok, _} =
  Works.insert_node(%{
    work_id: work.id,
    section_id: s.id,
    node_type: "beat",
    title: "Cold kettle, nobody moves",
    quote: "The kettle went cold on the counter. Nobody moved to fill it again."
  })

[page] = Reading.page(work)
```
- assert page.unplaced == []
- `[block] = Enum.filter(page.blocks, &(&1.notes != []))` (match: exactly one block carries notes)
- assert block.text =~ "She had been standing"
- assert block.text =~ "Nobody moved to fill it again."
(3)

### test "editing one sentence supersedes only the note on that sentence"  (`%{work: work, section: s}`)
Two nodes via Works.insert_node, both with `work_id: work.id, section_id: s.id, node_type: "beat"`:
- kettle: title "The kettle", quote "The kettle went cold on the counter."
- window: title "The window", quote "It was the window."
```elixir
[_heading, first, _second] = String.split(s.body, "\n\n")
edited = String.replace(first, "The kettle went cold on the counter.", "The kettle boiled dry.")
{:ok, %{superseded: 1}} = Works.replace_block(s, first, edited)
statuses = work.id |> Works.list_nodes() |> Map.new(&{&1.id, &1.status})
```
- assert statuses[kettle.id] == "superseded"
- refute statuses[window.id] == "superseded"
(2; plus the match `{:ok, %{superseded: 1}}`.) `Works.replace_block/3` is (section, old_block_text, new_block_text) and returns `{:ok, %{superseded: n, section: s}}`. `Works.list_nodes/1` takes a work id; nodes have `:id` and `:status`.

### test "an edit of one sentence is one changed paragraph, and the diff names only that sentence"  (`%{work: work, section: s}`)
```elixir
[_heading, first, _] = String.split(s.body, "\n\n")
edited = String.replace(first, "Nobody moved to fill it again.", "Nobody moved.")
{:ok, _} = Works.replace_block(s, first, edited)

work = Works.get_work(work.user_id, work.id)
rows = Diff.rows(Works.baseline(work), work.body)
```
- assert [{:same, _, _}, {:change, before, aft}, {:same, _, _}] = rows
- assert Diff.stat(rows) == %{same: 2, changed: 1, added: 0, removed: 0}
- `changed_words = Diff.words(before, aft) |> Enum.reject(&match?({:same, _}, &1)) |> Enum.map_join(" ", fn {_, t} -> String.trim(t) end)`
- assert changed_words =~ "to fill it again"
- refute changed_words =~ "standing at the window"
(4)

### test "the stored form survives an edit pasted as one long line"  (`%{work: work, section: s}`)
```elixir
[_heading, _, second] = String.split(s.body, "\n\n")

pasted =
  "By evening the argument had found its real subject. It was the window. It always was."

{:ok, %{section: s}} = Works.replace_block(s, second, pasted)
```
- assert s.body =~ "By evening the argument had found its real subject.\nIt was the window.\nIt always was."
- `[rev] = Works.revisions(work.id)`; assert rev.after == "By evening the argument had found its real subject.\nIt was the window.\nIt always was."
(2) The revision's `after` is stored reflowed too.

### test "the page shows one block per paragraph, however many sentences it holds"  (`%{work: work}`)
```elixir
[page] = Reading.page(work)
```
- assert [heading, first, second] = page.blocks
- assert heading.text == "# A draft"
- assert first.text =~ "\n"
- assert second.text =~ "\n"
(4)

### test "an edit that only re-wraps a paragraph is no edit at all"  (`%{work: work, section: s}`)
```elixir
[_heading, first, _] = String.split(s.body, "\n\n")

rewrapped =
  first |> String.replace("\n", " ") |> String.replace("hour before", "hour\nbefore")

{:ok, %{superseded: 0}} = Works.replace_block(s, first, rewrapped)
```
- assert Works.revisions(work.id) == []
(1; plus the match `{:ok, %{superseded: 0}}`)

Behavior not obvious from the code:
- create_work stores `body` already reflowed; `baseline_body` equals that stored body (so a diff against baseline starts clean); `word_count` is the same whether or not wrapping is counted (words of the original text).
- A section title derived from the draft is the first full sentence with wrapping newlines closed up, not the default "Section 1" and not the first physical line.
- Anchor.verify returns the span of the stored text, so a quote spanning a sentence break comes back with "\n" where the flat quote had a space.
- Superseding is per quote: editing the kettle sentence supersedes the kettle note (quote inside the edited sentence) and not the window note (in the other paragraph).
- Whitespace-only differences (re-wrapping) produce no revision and supersede nothing (`superseded: 0`).
- Reading.page blocks are per paragraph (the heading `# A draft` is its own block), and a paragraph block's text contains the "\n" between sentences.

Assertion count: 24 (static).

---

## test/marginalia/reflow_test.exs  (12 tests; covers Marginalia.Works.Reflow wrapped?/1, reflow/1, align/2 with Marginalia.Analysis.Anchor.verify/2)

Module `Marginalia.Works.ReflowTest`, `async: true`, aliases `Marginalia.Analysis.Anchor`, `Marginalia.Works.Reflow`. Moduledoc: "Putting the paragraphs back into text that came out of a PDF. The sample is the real thing: the opening of the Landor opinion exactly as `pdftotext` handed it over, page furniture and all."

`@page` (heredoc, verbatim, ends with newline):
```
JUSTICE GORSUCH delivered the opinion of the Court.
This case concerns whether the Religious Land Use and
Institutionalized Persons Act of 2000 permits plaintiffs to
sue nonconsenting state employees in their private capaci-
ties for damages.
I
Today, Congress offers financial support to all 50 States
and many other entities. Much of that support comes with
strings attached. So, for example, Congress has conditioned
receipt of federal highway funds on a State's agreement to
maintain laws setting a minimum drinking age of 21. See
South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-
gress has conditioned federal Medicaid funds on a State's
willingness to administer its healthcare programs con-
sistent with various rules.
2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND
PUBLIC SAFETY
In each of these contexts and many others, the penalty for
noncompliance is straightforward: Congress may termi-
nate funds if a recipient fails to abide by the conditions
associated with its grants.
```
No blank lines. The line "I" is a division numeral; "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND" + "PUBLIC SAFETY" is a two-line running head with page number 2.

### describe "recognising page text"

#### test "hard-wrapped text with no blank lines is page text"
- assert Reflow.wrapped?(@page)   (wrapped?/1 -> boolean)
(1)

#### test "text that already has paragraphs is left alone"
```elixir
prose =
  Enum.map_join(1..8, "\n\n", fn i ->
    "Paragraph #{i}. " <> String.duplicate("word ", 30)
  end)
```
- refute Reflow.wrapped?(prose)
- assert Reflow.reflow(prose) == prose   (reflow/1 is the identity on it)
(2)

#### test "a couple of lines is not enough to guess from"
- refute Reflow.wrapped?("one line\nand another")
(1)

### describe "reflowing"
`setup do: %{out: Reflow.reflow(@page)}` (context key `out`).

#### test "the paragraphs come back"
`paras = String.split(out, "\n\n")`
- assert length(paras) >= 4
- assert Enum.any?(paras, &String.starts_with?(&1, "JUSTICE GORSUCH"))
- assert Enum.any?(paras, &String.starts_with?(&1, "Today, Congress"))
- assert Enum.any?(paras, &String.starts_with?(&1, "In each of these contexts"))
(4)

#### test "a paragraph is one line, not eight"
`[first | _] = String.split(out, "\n\n")`
- refute String.contains?(first, "\n")
- assert first =~ "private capacities for damages."
(2)

#### test "the typesetter's hyphens are closed up"
- assert out =~ "private capacities"
- assert out =~ "Congress has conditioned federal Medicaid"
- assert out =~ "programs consistent with"
- assert out =~ "may terminate funds"
- refute out =~ "capaci-"
- refute out =~ "Con-\n"
(6)

#### test "a hyphen the document uses elsewhere is kept"
```elixir
page =
  "The statute permits removal only for cause, and the for-cause standard\n" <>
    "is the whole dispute. The parties agree that the ordinary for-\n" <>
    "cause rule governs here and nowhere else in the record.\n" <>
    String.duplicate("A further line of argument follows here at length.\n", 10)

out = Reflow.reflow(page)
```
- assert out =~ "the ordinary for-cause rule"
- refute out =~ "forcause"
(2)

#### test "the running head is dropped"
- refute out =~ "LANDOR v. LOUISIANA DEPT"
- refute out =~ "PUBLIC SAFETY"
(2)

#### test "the division numeral stands alone"
- assert "I" in String.split(out, "\n\n")   (a paragraph consisting solely of "I")
(1)

#### test "no word is lost"
```elixir
words = fn t ->
  t
  |> String.replace("-\n", "")
  |> String.split(~r/\s+/, trim: true)
  |> Enum.reject(&(&1 in ~w(2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND PUBLIC SAFETY)))
end
```
- assert length(words.(out)) >= length(words.(@page)) - 12
(1)

### describe "the anchoring contract"
Comment: "Whitespace is free -- Anchor normalises it -- but de-hyphenation changes characters, so a quote has to travel through the same transformation as the text it is anchored to."

#### test "a quote spanning a mended hyphen still verifies"
```elixir
out = Reflow.reflow(@page)
quote = "sue nonconsenting state employees in their private capaci-\nties for damages."
```
- assert {:ok, span} = Anchor.verify(Reflow.align(quote, @page), out)   (Reflow.align/2: quote, original page text -> quote transformed the same way)
- assert span =~ "private capacities for damages."
- assert String.contains?(out, span)
(3)

#### test "a quote with no hyphen in it verifies untouched"
```elixir
out = Reflow.reflow(@page)
quote = "Much of that support comes with\nstrings attached."
```
- assert {:ok, span} = Anchor.verify(Reflow.align(quote, @page), out)
- assert String.contains?(out, span)
(2)

Behavior not obvious from the code:
- `wrapped?` is a heuristic: many short lines with no blank lines. Two lines is too few to judge; text that already has blank-line paragraphs is not wrapped and reflow is the identity on it.
- Reflow output joins paragraphs with "\n\n" and each paragraph is one physical line (sentence splitting is a separate step).
- End-of-line hyphens are removed ("capaci-\nties" -> "capacities", "Con-\ngress", "termi-\nnate", "con-\nsistent") unless the document itself uses that hyphenated compound elsewhere ("for-cause" stays "for-cause", never "forcause"): the document's own usage decides.
- Page furniture: "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND" with the following "PUBLIC SAFETY" is dropped as a running head; a bare "I" line becomes its own paragraph.
- Reflow.align(quote, original) must apply the same de-hyphenation to a quote copied from the raw text so Anchor.verify on the reflowed text succeeds.
- "No word is lost" tolerates a loss of up to 12 tokens (the running-head words and numerals are excluded from both sides first).

Assertion count: 27 (static).

---

## test/marginalia/diff_test.exs  (10 tests; covers Marginalia.Diff rows/2, stat/1, any?/1, words/2)

Module `Marginalia.DiffTest`, `async: true`, alias `Marginalia.Diff`. Moduledoc: "Aligning two versions of a draft. The alignment is the whole job. Zipping the two lists and comparing by position marks everything after an inserted paragraph as changed, which is a diff nobody can read." Helper `p(list)` = `Enum.join(list, "\n\n")`. Pure; no DB.

Row shapes: `{:same, left, right}`, `{:change, left, right}`, `{:ins, text}`, `{:del, text}`. `Diff.stat(rows)` -> `%{same:, changed:, added:, removed:}`. `Diff.words(l, r)` -> list of `{:same, t}` / `{:ins, t}` / `{:del, t}` pieces.

### test "identical prose is all same"
`text = p(["One.", "Two.", "Three."])`; `rows = Diff.rows(text, text)`
- assert Enum.all?(rows, &match?({:same, _, _}, &1))
- refute Diff.any?(rows)   (any?/1: true if any row is not :same)
(2)

### test "an edited paragraph is a change, not a delete and an insert"
`rows = Diff.rows(p(["One.", "Two.", "Three."]), p(["One.", "Two, amended.", "Three."]))`
- assert [{:same, "One.", "One."}, {:change, "Two.", "Two, amended."}, {:same, _, _}] = rows
- assert Diff.stat(rows).changed == 1
(2)

### test "a paragraph inserted in the middle shifts nothing after it"
`rows = Diff.rows(p(["One.", "Two."]), p(["One.", "INSERTED.", "Two."]))`
- assert [{:same, "One.", _}, {:ins, "INSERTED."}, {:same, "Two.", _}] = rows
- assert Diff.stat(rows) == %{same: 2, changed: 0, added: 1, removed: 0}
(2)

### test "a removed paragraph is a delete, and the rest still lines up"
`rows = Diff.rows(p(["One.", "GONE.", "Three."]), p(["One.", "Three."]))`
- assert [{:same, "One.", _}, {:del, "GONE."}, {:same, "Three.", _}] = rows
- assert Diff.stat(rows).removed == 1
(2)

### test "rewrapping is not an edit"
```elixir
a = "A sentence that\nwraps across lines."
b = "A sentence that wraps   across lines."
```
- assert [{:same, _, _}] = Diff.rows(a, b)   (whitespace, including newlines, is normalised before comparing)
(1)

### test "a changed pair carries a word-level diff inside it"
`[{:change, l, r}] = Diff.rows("The kettle went cold.", "The kettle went stone cold.")`; `parts = Diff.words(l, r)`
- assert Enum.any?(parts, &match?({:ins, _}, &1))
- assert Enum.any?(parts, &match?({:same, _}, &1))
(2)

### test "several edits in a row pair up rather than stacking"
`rows = Diff.rows(p(["A.", "B.", "C."]), p(["A1.", "B1.", "C1."]))`
- assert length(rows) == 3
- assert Enum.all?(rows, &match?({:change, _, _}, &1))
(2)

### test "more new paragraphs than old leaves the extra as inserts"
`rows = Diff.rows(p(["A."]), p(["A1.", "B.", "C."]))`
- assert Enum.count(rows, &match?({:change, _, _}, &1)) == 1
- assert Enum.count(rows, &match?({:ins, _}, &1)) == 2
(2)

### test "empty sides do not crash"
- assert Diff.rows("", "") == []
- assert Enum.all?(Diff.rows("", p(["A.", "B."])), &match?({:ins, _}, &1))
- assert Enum.all?(Diff.rows(p(["A.", "B."]), ""), &match?({:del, _}, &1))
- assert Diff.rows(nil, nil) == []
(4)

### test "a real-sized draft aligns in reasonable time"
```elixir
old = p(for i <- 1..120, do: "Paragraph #{i}. " <> String.duplicate("word ", 60))

new =
  p(
    for i <- 1..120,
        do:
          if(i == 75,
            do: "Paragraph 75 REWRITTEN.",
            else: "Paragraph #{i}. " <> String.duplicate("word ", 60)
          )
  )

{micros, rows} = :timer.tc(fn -> Diff.rows(old, new) end)
```
- assert Diff.stat(rows).changed == 1
- comment: "A wall-clock bound in a suite that runs 24 cases in parallel measures the machine's load as much as the code, and a tight one here failed once on a busy run and then passed six times. The number is loose on purpose: it is a guard against someone making this accidentally cubic, not a benchmark. The real assertion is the line above."
- assert micros < 20_000_000, "120 paragraphs took #{div(micros, 1000)}ms"   (20 seconds)
(2)

Behavior not obvious from the code:
- Alignment is by content (LCS-style), not by position: an inserted paragraph does not mark the following paragraphs as changed.
- A delete+insert at the same alignment gap becomes a `:change` pair (edited paragraph); extra new paragraphs beyond the old ones become `:ins`; extra old ones become `:del`.
- Comparison ignores whitespace differences, so re-wrapping is `:same`.
- nil is treated as empty.
- Performance guard: 120 paragraphs x 60 words must align well under 20 seconds (must not be cubic).

Assertion count: 21 (static).

---

## test/marginalia/selection_test.exs  (16 tests; covers Marginalia.Selection rendered_text/1, squash/1, in_block/2, locate/2 and Analysis.Anchor.verify/2)

Module `Marginalia.SelectionTest`, `use Marginalia.DataCase, async: true`, aliases `Marginalia.{Selection, Works}`, `import Marginalia.AccountsFixtures`. Moduledoc: "A selection is made against rendered text; the draft is markdown. Three earlier attempts encoded the ways those differ -- strip backticks, blank out link targets, blank out list markers -- and each fixed one construct while leaving every other one broken. This aligns the page back to the source instead, so there is no markdown knowledge to be incomplete. Every case below is a construct nobody had to write a rule for." (Original text uses em dashes.)

Helpers:
```elixir
# select the middle of a block the way a person drags across it
defp select(source) do
  source
  |> Selection.rendered_text()
  |> Selection.squash()
  |> String.split(" ", trim: true)
  |> then(fn w -> w |> Enum.slice(1, max(length(w) - 2, 2)) |> Enum.join(" ") end)
end

defp roundtrip(source) do
  sel = select(source)
  span = Selection.in_block(source, sel)

  assert span, "nothing matched for #{inspect(sel)}"
  assert String.contains?(source, span), "the span must be a literal substring of the draft"

  # and it must actually cover what was selected
  for word <- sel |> String.split(" ") |> Enum.take(3) do
    assert String.contains?(span, word), "span #{inspect(span)} is missing #{inspect(word)}"
  end

  span
end
```
So `Selection.rendered_text(markdown) -> text as a browser would render it`, `Selection.squash(text) -> whitespace-collapsed`, `Selection.in_block(source, selection) -> literal substring of source (truthy) or nil/false`. The "selection" is the rendered words with the first word and the last word dropped (slice(1, max(n-2, 2))). The roundtrip helper has 3 static assertions (assert span; assert contains; assert in `for`, executed for up to 3 words); each of the 11 tests below runs it once. Each of the 11 tests has no other assertion.

### describe "constructs nobody wrote a rule for"
Each test is `roundtrip(<source>)`; the source strings are:
- test "links": `"Ten years ago, [I wrote a runner](https://x.test/p) after Jose said so."`
- test "code spans": `"We will use `gen_stage`, which happens *elsewhere* entirely."`  (backticks around gen_stage)
- test "numbered lists": `"1. The purpose of society is to make people better off\n2. In general it is hard"`
- test "bullets": `"- a bullet item here\n- another bullet entirely"`
- test "blockquotes": `"> a quoted line here for us to read"`
- test "tables": `"| who | named |\n|---|---|\n| Dario | yes |"`
- test "headings": `"## Step 4: Creating the Producer"`
- test "entities": `"Tom &amp; Jerry went to the shop today"`
- test "nested emphasis": `"This is **bold with _nested_ emphasis** inside it"`
- test "images": `"Look at ![a diagram](/img/x.png) closely now please"`
- test "fenced code": `"```elixir\ndef handle(demand, state) do\n  {:noreply, [], state}\nend\n```"`

### describe "locate/2"
`setup` (each test):
```elixir
user = user_fixture()

body =
  "# A draft\n\nShe stood at the [window](https://x.test) for an hour.\n\n" <>
    "1. The purpose of society is to make those living in it better off\n" <>
    "2. In general, it is better to make the less well off better off\n\n" <>
    String.duplicate("word ", 300)

{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
%{work: work}
```
(`Works.create_work/2` reflows the body to sentence-per-line on the way in; `Selection.locate(work, selection_string)` searches the work's sections.)

#### test "finds a selection and returns the source span"
- assert {:ok, %{span: span, section: section}} = Selection.locate(work, "She stood at the window for an hour")
- assert String.contains?(work.body, span)
- assert span =~ "[window](https://x.test)"
- assert section.ordinal == 1
(4)

#### test "a selection dragged across a paragraph break still lands"
`sel = "for an hour. The purpose of society is to make those living in it better off"`
- assert {:ok, %{span: span}} = Selection.locate(work, sel)
- assert String.contains?(work.body, span)
(2)

#### test "something not in the draft is refused"
- assert Selection.locate(work, "a sentence that appears nowhere at all") == :error
(1)

#### test "a stray click is refused"
- assert Selection.locate(work, "the") == :error   (a one-word / too-short selection is rejected)
(1)

### test "the strict matcher the beats rely on is untouched"
`alias Marginalia.Analysis.Anchor`; `src = "1. The purpose of society is to make people better off"`
- comment: "it matches literally, folding only whitespace and typography"
- assert {:ok, "1. The purpose of society"} = Anchor.verify("1. The purpose of society", src)
- assert {:ok, _} = Anchor.verify("The  purpose\nof society", src)
- comment: "and it still refuses a reordering, which is the guarantee the beats rest on"
- assert Anchor.verify("society of purpose the", src) == :error
(3)

Behavior not obvious from the code:
- The aligner works from rendered text back to source rather than from rules per construct: any markdown construct (links, code spans, list markers, blockquote `>`, table pipes, headings, entities like `&amp;`, nested emphasis, images, fenced code with info string) must yield a span that is a literal substring of the source and contains the first three selected words.
- A locate result returns the span as raw markdown source (it includes `[window](https://x.test)` even though the user selected "window"), plus the section (section.ordinal is 1-based).
- A selection that crosses a paragraph boundary (across "\n\n") still resolves.
- Unmatched text and tiny selections return the bare atom `:error` (not a tuple).
- `Anchor.verify/2` is deliberately separate and strict: literal match modulo whitespace/typography only, reordering is refused.

Assertion count: 14 (11 direct + 3 in the roundtrip helper, which every roundtrip test executes).

---

## test/marginalia/markdown_test.exs  (2 tests; covers Marginalia.Markdown.to_html/2)

Module `Marginalia.MarkdownTest`, `async: true`, alias `Marginalia.Markdown`. `to_html/1,2` returns `{:safe, iodata}`.

### test "a reply keeps its line breaks"
```elixir
{:safe, html} = Markdown.to_html("one\ntwo")
```
- assert IO.iodata_to_binary(html) =~ "<br"
(1)

### test "a draft joins the sentences of a paragraph and keeps its paragraphs"
```elixir
{:safe, html} = Markdown.to_html("One.\nTwo.\n\nThree.", breaks: :soft)
html = IO.iodata_to_binary(html)
```
- refute html =~ "<br"
- assert html =~ "<p>One.\nTwo.</p>"
- assert html =~ "<p>Three.</p>"
(3)

Behavior not obvious from the code:
- Default option turns a single newline into `<br>`; `breaks: :soft` leaves the newline as a literal "\n" inside the `<p>` (no `<br>`), which is how one-sentence-per-line drafts render as one paragraph.

Assertion count: 4 (static).

---

## test/marginalia/anchor_test.exs  (11 tests; covers Marginalia.Analysis.Anchor verify/2, filter/2)

Module `Marginalia.Analysis.AnchorTest`, `async: true`, alias `Marginalia.Analysis.Anchor`. Pure; no DB. `Anchor.verify(quote, source)` returns `{:ok, span}` (span is the matching text from the source) or `:error`. `Anchor.filter(nodes, source)` returns `{kept_nodes, dropped_count}`.

`@source` (heredoc; the first two lines are long lines, ends with newline):
```
She had been standing at the window for an hour before anyone noticed, and by then the
light had gone completely. "You can't keep doing this," her brother said, from the doorway.
He did not come in.
```
(straight ASCII quotes and apostrophe in the source.)

### test "an exact quote verifies"
- assert {:ok, q} = Anchor.verify("standing at the window for an hour", @source)
- assert q == "standing at the window for an hour"
(2)

### test "curly quotes and dashes are normalised away"
- assert {:ok, _} = Anchor.verify("“You can’t keep doing this,” her brother said", @source)   (curly double quotes U+201C/U+201D and curly apostrophe U+2019 in the quote; source has straight)
(1)

### test "a fabricated quote is rejected"
- assert :error = Anchor.verify("She turned and left without saying anything at all", @source)
(1)

### test "a too-short quote is rejected rather than trivially matched"
- assert :error = Anchor.verify("the", @source)
(1)

### describe "paraphrase is not verbatim"
`@para "She kept them in the freezer, which she never explained to anyone, and by then it hardly mattered."`

#### test "the same words in a different order are rejected"
Comment: "the old matcher scored set membership over a sliding window, which is order-blind, so a rearranged sentence anchored"
- assert :error = Anchor.verify("the freezer she kept them in which she never explained", @para)
(1)

#### test "a deleted negation is rejected"
Comment: "the worst case: this used to anchor AND return a span still containing "never", storing the opposite of what the model claimed"
- assert :error = Anchor.verify("which she explained to anyone, and by then it hardly mattered", @para)
(1)

#### test "a dropped word is rejected"
- assert :error = Anchor.verify("had been standing at window for an hour before anyone noticed", @source)   (missing "the" before "window")
(1)

#### test "a substituted word is rejected"
- assert :error = Anchor.verify("standing at the doorway for an hour", @source)
(1)

#### test "but typography and line wrapping are still absorbed"
```elixir
wrapped = "She kept them in the\nfreezer, which she never\nexplained to anyone."
```
- assert {:ok, span} = Anchor.verify("She kept them in the freezer, which she never explained", wrapped)
- assert String.contains?(wrapped, span)   (the returned span is a literal substring of the wrapped source, i.e. it includes the original "\n"s)
(2)

### test "filter keeps anchored nodes and counts the discards"
```elixir
nodes = [
  %{title: "real", quote: "He did not come in."},
  %{title: "invented", quote: "She screamed at the top of her lungs and ran."},
  %{title: "also real", quote: "by then the light had gone completely"}
]

{kept, dropped} = Anchor.filter(nodes, @source)
```
- assert dropped == 1
- assert Enum.map(kept, & &1.title) == ["real", "also real"]
(2)  Note: "by then the light had gone completely" spans the line break in @source ("by then the\nlight had gone completely").

### test "a node with no quote at all is discarded"
- assert {[], 1} = Anchor.filter([%{title: "unsourced", quote: nil}], @source)
(1)

Behavior not obvious from the code:
- Verification is literal, order-sensitive and word-exact; only whitespace (incl. newlines) and typography (curly quotes, dashes) are folded. A dropped, substituted, reordered or negation-deleted quote is `:error`.
- Very short quotes (e.g. "the") are rejected even though they occur in the source.
- On success the span returned is taken from the source (so it keeps the source's own punctuation/line breaks), which is what lets callers store it verbatim.
- filter/2 preserves input order of kept nodes, and nodes with `quote: nil` are counted as dropped.

Assertion count: 14 (static).

---

## test/marginalia/kinship_test.exs  (8 tests; covers Marginalia.Cases.Kinship terms/1 and pairs/2)

Module `Marginalia.Cases.KinshipTest`, `async: true`, alias `Marginalia.Cases.Kinship`. Moduledoc: "Which cases are about the same thing as which other cases. The first attempt scored the read pass's own commentary, which has one author across every document, so it measured writing style: the top pairs shared "inversion", "breath" and "demolition". Scoring the anchored quotes instead scores the judges' own words."

Helper: `defp bag(text), do: Kinship.terms([text])` -- `Kinship.terms/1` takes a list of strings and returns a `MapSet` of terms. `Kinship.pairs(bags, limit)` takes a map `doc_id => MapSet` and a max count, and returns a list of maps `%{a:, b:, shared: [terms], score: number}` sorted best first. Pure; no DB.

### describe "terms"

#### test "a word used once is not what a document is about"
- assert MapSet.member?(bag("removal removal of officers"), "removal")
- refute MapSet.member?(bag("removal of officers"), "removal")
(2)

#### test "plurals and singulars are the same word"
- assert MapSet.member?(bag("warrants and warrant"), "warrant")
- assert MapSet.member?(bag("agencies and agency policies policies"), "agency")
(2)  ("warrants"+"warrant" count as two uses of "warrant"; "agencies"+"agency" two uses of "agency" -- "policies" twice is irrelevant to the assertion)

#### test "furniture is dropped"
```elixir
terms = bag("the court held that the court held that the opinion says the opinion says")
```
- assert MapSet.size(terms) == 0   (the words court, held, opinion, says, that, the are stop/furniture words even when repeated)
(1)

#### test "short words are dropped"
- refute MapSet.member?(bag("the writ the writ"), "writ")
(1)

### describe "pairs"
`setup`:
Comment: "Two pairs that share something, and filler. A term has to be in at least two documents to be shared at all and in no more than a third of them to be distinctive, so the fixtures have to be a corpus rather than a handful."
```elixir
bags =
  %{
    1 => bag("alien alien border border unique_one unique_one"),
    2 => bag("alien alien border border unique_two unique_two"),
    3 => bag("glyphosate glyphosate labeling labeling unique_three unique_three"),
    4 => bag("glyphosate glyphosate labeling labeling unique_four unique_four"),
    5 => bag("citizenship citizenship unique_five unique_five"),
    6 => bag("sovereign sovereign unique_six unique_six")
  }

%{bags: bags}
```

#### test "documents about the same thing find each other"  (`%{bags: bags}`)
```elixir
pairs = Kinship.pairs(bags, 10)
found = Enum.map(pairs, &Enum.sort([&1.a, &1.b]))
```
- assert [1, 2] in found
- assert [3, 4] in found
- comment: "nothing distinctive ties the filler to anything"
- refute Enum.any?(found, &(5 in &1 or 6 in &1))
(3)

#### test "each pair names what it is that they share"  (`%{bags: bags}`)
```elixir
top = Kinship.pairs(bags, 10) |> Enum.find(&(Enum.sort([&1.a, &1.b]) == [1, 2]))
```
- assert "alien" in top.shared
- assert "border" in top.shared
- assert top.score > 0
(3)

#### test "a pair with nothing distinctive in common is not a pair"
```elixir
bags = %{
  1 => bag("glyphosate glyphosate labeling labeling"),
  2 => bag("citizenship citizenship jurisdiction jurisdiction")
}
```
- assert Kinship.pairs(bags, 10) == []
(1)

#### test "length is divided out, so the biggest document is not everyone's kin"
Comment above test: "The longest document had the most chances to coincide, and came out as everyone's nearest relation."
```elixir
long = Enum.map_join(1..400, " ", fn i -> "filler#{i} filler#{i}" end)

bags = %{
  1 => bag("alien alien border border " <> long),
  2 => bag("alien alien border border"),
  3 => bag("glyphosate glyphosate labeling labeling"),
  4 => bag("glyphosate glyphosate labeling labeling")
}

[top | _] = Kinship.pairs(bags, 10)
```
- assert Enum.sort([top.a, top.b]) == [3, 4], message "the pair with a huge document in it outscored the clean one"
(1)

Behavior not obvious from the code:
- Terms: a word needs at least 2 occurrences in the document to count; plural/singular are merged (warrants/warrant, agencies/agency); courtroom "furniture" words (the, court, held, that, opinion, says) and short words (about 4 letters or fewer, "writ") are dropped even when repeated.
- Pairs use only terms that appear in at least two documents and in no more than a third of the documents (the "distinctive" rule). In the six-document setup "alien"/"border" are in 2 of 6 (a third), "glyphosate"/"labeling" in 2 of 6; the filler terms (citizenship, sovereign, unique_*) appear in one document and tie nothing together.
- In the two-document case ("a pair with nothing distinctive in common") nothing is shared at all, so the result is `[]`.
- In the length test, document 1 carries 400 extra repeated filler terms (each used twice, so each counts as a term). Without dividing by length it would collect the most coincidences; scoring normalises for size so the clean (3,4) pair must be first in the returned list. Exact thresholds and the score formula are in lib/marginalia/cases/kinship.ex, not in the test.

Assertion count: 14 (static).

---

## test/marginalia/outline_test.exs  (5 tests; covers Marginalia.Reading.outline/1 over Reading.page/1)

Module `Marginalia.OutlineTest`, moduledoc "The draft's headings, for jumping around it.", `use Marginalia.DataCase, async: true`, aliases `Marginalia.{Reading, Works}`, `import Marginalia.AccountsFixtures`.

`setup` (every test):
Comment: "the segmenter promotes # to ### into sections of their own, so the headings that stay *inside* a section are the deeper ones"
```elixir
user = user_fixture()

body =
  "# What are we talking about?\n\n" <>
    String.duplicate("word ", 300) <>
    "\n\n#### A sub heading\n\nMore prose here.\n\n" <>
    "##### Deeper still\n\nYet more prose.\n\n" <>
    String.duplicate("other ", 300)

{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
%{page: Reading.page(work)}
```
`Reading.page(work)` returns a list of per-section maps, each with `.section` (with `.ordinal`) and `.blocks` (each with `.ref`). `Reading.outline(page)` returns a list of entries with `:title`, `:level`, `:id`, `:words`.

### test "sections and the headings inside them, in order"  (`%{page: page}`)
`titles = page |> Reading.outline() |> Enum.map(& &1.title)`
- assert "What are we talking about?" in titles
- assert "A sub heading" in titles
- assert "Deeper still" in titles
- assert Enum.find_index(titles, &(&1 == "A sub heading")) < Enum.find_index(titles, &(&1 == "Deeper still"))
(4)

### test "each entry points at an element that exists on the page"  (`%{page: page}`)
```elixir
refs =
  page
  |> Enum.flat_map(fn s -> Enum.map(s.blocks, &"block-#{&1.ref}") end)
  |> MapSet.new()

sections = page |> Enum.map(&"sec-#{&1.section.ordinal}") |> MapSet.new()
ids = MapSet.union(refs, sections)

for e <- Reading.outline(page) do
  assert MapSet.member?(ids, e.id), "#{e.id} is not on the page"
end
```
(1 static) So entry ids are `"block-<ref>"` for in-section headings and `"sec-<ordinal>"` for sections.

### test "nesting is carried as a level"  (`%{page: page}`)
`by_title = page |> Reading.outline() |> Map.new(&{&1.title, &1.level})`
- assert by_title["A sub heading"] == 4
- assert by_title["Deeper still"] == 5
(2)

### test "a section is not listed twice under its own title"  (`%{page: page}`)
```elixir
entries = Reading.outline(page)
titles = Enum.map(entries, & &1.title)
```
- assert length(titles) == length(Enum.uniq(titles))
(1)  (the section's own leading "# What are we talking about?" heading block must not also appear as a separate entry)

### test "sections carry their length"  (`%{page: page}`)
- assert [%{level: 0, words: w} | _] = Reading.outline(page)   (first entry is the section, level 0)
- assert w > 0
(2)

Behavior not obvious from the code:
- Sections are level 0 entries with a `words` count; headings inside sections are entries with level equal to the number of `#` (4 and 5 here). `#` to `###` headings become sections of their own via the segmenter, so only deeper headings appear as in-section entries.
- The body is one `#` heading plus about 600 words; the work lands in one section titled "What are we talking about?" (title taken from its heading), and that title appears once in the outline.

Assertion count: 10 (static).

---

## test/marginalia/editor_tools_test.exs  (8 tests; covers Marginalia.Chat.Editor tools/0, system_prompt/0, run_call/2; Works.list_corrections/1, Works.insert_nodes/3, Works.link/6, Chat.get_or_create_conversation/1, Chat.append/3)

Module `Marginalia.Chat.EditorToolsTest`, `use Marginalia.DataCase, async: true`, aliases `Marginalia.Chat.Editor`, `Marginalia.{Chat, Works}`, `import Marginalia.AccountsFixtures`. Moduledoc: "The system prompt names tools by hand. For three releases it named two that did not exist -- `record_correction` and `recall_sessions` -- so every promise to remember a ruling was empty. This pins prompt and tool surface together." No LLM is called (tools are invoked directly; no put_env, no stubs).

`setup` (every test):
```elixir
user = user_fixture()
body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
%{work: work, section: hd(Works.list_sections(work.id))}
```

Helpers:
```elixir
defp names, do: Enum.map(Editor.tools(), & &1["function"]["name"])

defp call(work, name, args) do
  fun = %{"id" => "x", "function" => %{"name" => name, "arguments" => Jason.encode!(args)}}
  :erlang.apply(Editor, :run_call, [work, fun])["content"] |> Jason.decode!()
end
```
So `Editor.tools()` is a list of OpenAI-style tool defs (`%{"function" => %{"name" => ...}}`); `Editor.run_call(work, tool_call_map)` returns a tool-message map whose `"content"` is a JSON string. `call/3` returns the decoded JSON of that content. (Called through `:erlang.apply` so the compiler does not warn about a non-public or typed signature.)

### test "every tool the prompt tells the model to call actually exists"
```elixir
prompt = Editor.system_prompt()

for name <- names() do
  assert is_binary(name)
end

# any lower_snake_case token in the prompt that looks like a tool call
mentioned =
  Regex.scan(~r/\b([a-z][a-z_]{4,})\b(?=\s|,|\.|\)|$)/m, prompt)
  |> Enum.map(&List.last/1)
  |> Enum.uniq()

# the ones that are unambiguously tool names: they appear in our list, or
# they are named in a "call X" construction
called =
  Regex.scan(~r/call(?:ing)?\s+`?([a-z_]{4,})`?/, prompt)
  |> Enum.map(&List.last/1)
  |> Enum.uniq()
```
- for each name in names(): assert is_binary(name)   (executed per tool)
- for c <- called: assert c in names(), message "the prompt says to call #{c}/0 but there is no such tool"
- assert "search_manuscript" in mentioned   (the prompt text contains the token `search_manuscript` followed by whitespace, comma, period, `)` or end of line)
(3 static)

### test "the connections tool exposes the cross-section pass"
- assert "connections" in names()
(1)

### describe "record_correction"

#### test "a misread is stored and comes back from recall"  (`%{work: work}`)
```elixir
out = call(work, "record_correction", %{"kind" => "misread", "about" => "Del leaves in ch 3"})
```
- assert out["recorded"] == "misread"
```elixir
recalled = call(work, "recall_sessions", %{})
```
- assert [%{"kind" => "misread", "about" => "Del leaves in ch 3"}] = recalled["corrections"]
(2)

#### test "a ruling keeps the writer's own words"  (`%{work: work}`)
```elixir
call(work, "record_correction", %{
  "kind" => "ruling",
  "about" => "the prologue should go",
  "ruling" => "I want the prologue. It stays."
})
```
- assert [c] = Works.list_corrections(work.id)
- assert c.kind == "ruling"
- assert c.ruling == "I want the prologue. It stays."
(3)

#### test "an unknown kind is refused rather than stored"  (`%{work: work}`)
```elixir
out = call(work, "record_correction", %{"kind" => "vibes", "about" => "x"})
```
- assert out["error"] =~ "not recorded"
- assert Works.list_corrections(work.id) == []
(2)

### describe "recall_sessions"

#### test "finds what was said in an earlier conversation"  (`%{work: work}`)
```elixir
{:ok, c} = Chat.get_or_create_conversation(work.id)
Chat.append(c.id, "user", "I am worried the prologue is doing nothing")
Chat.append(c.id, "assistant", "The prologue introduces nobody who returns")

out = call(work, "recall_sessions", %{"query" => "prologue"})
```
- assert length(out["earlier_talk"]) == 2
- assert Enum.any?(out["earlier_talk"], &(&1["who"] == "assistant"))
(2)  Each hit is a JSON object with `"who"` ("user"/"assistant").

#### test "no query returns the corrections alone"  (`%{work: work}`)
```elixir
out = call(work, "recall_sessions", %{})
```
- assert out["earlier_talk"] == []
(1)

### describe "connections"

#### test "reports the cross-section edges with their reasons"  (`%{work: work, section: s}`)
```elixir
[a, b] =
  Works.insert_nodes(work.id, s.id, [
    %{node_type: "beat", title: "The promise"},
    %{node_type: "beat", title: "The payoff"}
  ])

Works.link(work.id, a.id, b.id, "pays_off", 0, "the opening promise lands here")

out = call(work, "connections", %{})
```
(`Works.insert_nodes/3` returns the inserted nodes as a bare list `[a, b]` in order; `Works.link/6` is (work_id, from_id, to_id, type, a 0 argument, reason).)
- assert [%{"type" => "pays_off", "why" => "the opening promise lands here"}] = out   (the decoded content is a JSON array of connection objects)
- assert call(work, "connections", %{"type" => "tension"}) == %{"result" => "no cross-section connections were drawn for this draft yet"}   (filtering to a type with no edges returns a map with this exact string)
(2)

Behavior not obvious from the code:
- The pinned property: every tool named after "call"/"calling" in the system prompt exists in `Editor.tools()`; `search_manuscript` is mentioned in the prompt; `record_correction`, `recall_sessions` and `connections` exist as tools.
- record_correction accepts kinds including "misread" and "ruling" and refuses an unknown one ("vibes") with an `"error"` string containing "not recorded" and stores nothing. A ruling carries `ruling` text verbatim.
- recall_sessions with `"query"` searches chat messages of the work's conversation(s) (case: both messages contain "prologue") and returns them under `"earlier_talk"` with `"who"`; without a query `"earlier_talk"` is `[]` and corrections are returned under `"corrections"` (each with `"kind"`, `"about"`).
- connections reports edges as `[%{"type", "why", ...}]`.

Assertion count: 16 (static).

---

## test/marginalia/beat_density_test.exs  (5 tests; covers Marginalia.Analysis beat_target/1, beat_ceiling/1, thin/3, beats_tool/0)

Module `Marginalia.BeatDensityTest`, `use Marginalia.DataCase, async: true`, aliases `Marginalia.{Analysis, Works}`, `import Marginalia.AccountsFixtures`. Moduledoc: "The section pass returned 8-10 beats for a 574-word section however plainly the prompt asked for two. A target alone is ignored; a stated limit is obeyed for short sections and still overshot for long ones, so the limit is enforced here too." (en dash in original.)

For reference, lib/marginalia/analysis.ex (not in the test) defines: `beat_target(w) = w |> div(220) |> max(2) |> min(14)`; `beat_ceiling(w) = t + max(div(t, 2), 1)` where `t = beat_target(w)`; `thin(beats, ceiling, section_id)` returns beats unchanged when `length <= ceiling`, otherwise picks `ceiling` evenly spaced elements: `step = (n - 1) / (ceiling - 1)`, indices `round(i * step)` for i in 0..ceiling-1, then `Enum.uniq`.

### describe "the target"

#### test "scales with the section, with a floor and a cap"
- assert Analysis.beat_target(100) == 2
- assert Analysis.beat_target(1_100) == 5
- assert Analysis.beat_target(100_000) == 14
(3)

#### test "the limit leaves room above the target without licensing a list"
`for words <- [100, 574, 1_309, 5_000]`: `t = Analysis.beat_target(words)`; `c = Analysis.beat_ceiling(words)`
- assert c > t, "the limit must leave room for a dense section"
- assert c < t * 2, "the limit must not license twice the target"
(2 static, 8 executed. With the formula above: 100 -> t=2,c=3; 574 -> t=2,c=3; 1309 -> t=5,c=7; 5000 -> t=14... wait, 5000 div 220 = 22, capped to 14, c=21; 21 < 28.)

### describe "thinning an over-long answer"
`setup`:
Comment: "one long section, so the ceiling bites"
```elixir
user = user_fixture()
body = "# One\n\n" <> String.duplicate("word ", 1_300)
{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
%{work: work, section: hd(Works.list_sections(work.id))}
```

#### test "keeps the section covered end to end rather than truncating it"  (`%{work: work, section: section}`)
```elixir
ceiling = Analysis.beat_ceiling(section.word_count)

beats =
  for i <- 1..(ceiling * 3) do
    %{node_type: "beat", title: "beat #{i}", quote: nil}
  end

kept = :erlang.apply(Analysis, :thin, [beats, ceiling, section.id])
```
- assert length(kept) == ceiling
- comment: "the first and last survive: truncation would drop the end of the section, which is worse than having too many beats"
- assert hd(kept).title == "beat 1"
- assert List.last(kept).title == "beat #{ceiling * 3}"
- assert work.id   (truthy; only there to use the variable)
(4)  Section word_count here is 1,301 (the "#", "One" and 1,300 "word"), hence ceiling = beat_ceiling(1301) = 7 (target 5).

#### test "leaves a normal answer alone"  (`%{section: section}`)
```elixir
beats = for i <- 1..3, do: %{title: "beat #{i}"}
```
- assert :erlang.apply(Analysis, :thin, [beats, 10, section.id]) == beats
(1)

### test "the section pass is a tool call, so the shape is enforced not requested"
```elixir
tool = Analysis.beats_tool()
item = tool["function"]["parameters"]["properties"]["beats"]["items"]
```
- assert tool["function"]["name"] == "record_beats"
- assert Enum.sort(item["required"]) == ["note", "quote", "title"]
(2)

Behavior not obvious from the code:
- Target is 1 beat per 220 words, floor 2, cap 14. Ceiling is the target plus half the target (at least one extra), strictly above the target and strictly under twice the target for the tested sizes.
- Thinning picks evenly spaced beats so the first and last survive (not a truncation); it does nothing when the count is within the ceiling (10 vs 3 beats returns the list identical).
- The beats tool is OpenAI-style function-call schema: name `record_beats`, a `beats` array whose items require exactly `note`, `quote`, `title`.
- Comments: "Measured, not guessed: the model returns whatever number it is given as a hard limit, and ignores a target on its own" (from lib).

Assertion count: 12 (static).

---

## test/marginalia/effort_test.exs  (2 test statements; 6 runtime tests; covers source-file inspection of reasoning-effort settings)

Module `Marginalia.EffortTest`, `use ExUnit.Case, async: true`. Moduledoc: "Reasoning tokens are billed as output and are never cached, so which passes think hard is the biggest single lever on the bill. This pins the choice so a future edit cannot quietly turn it back up everywhere."

This test does not call the code; it reads Elixir source files relative to the repo root (cwd when `mix test` runs) and greps them. For the rewrite it is a spec of which LLM passes use which reasoning effort and where the default lives; port it to whatever the equivalent source/config check is, or as a call-site check.

Comment on `@sources`: "the call sites, read out of the source rather than restated, so this test fails if the effort moves rather than passing on a stale copy of it"
```elixir
@sources %{
  "per-section beats" => {"lib/marginalia/analysis.ex", "@beats_prompt", :none},
  "the spine" => {"lib/marginalia/analysis.ex", "@spine_prompt", :high},
  "the weave" => {"lib/marginalia/analysis/weave.ex", "@weave_prompt", :high},
  "the narratives" => {"lib/marginalia/analysis/decision_graph.ex", "@narrative_prompt", :high},
  "the graph build" => {"lib/marginalia/analysis/decision_graph.ex", "@graph_prompt", :high}
}
```

### test "effort is set per call, not per deploy"
```elixir
body = File.read!("lib/marginalia/llm.ex")
```
- assert body =~ "put_effort"
- assert body =~ ~s(default_body: %{"reasoning_effort" => "low"})
(2) i.e. llm.ex has a per-call `put_effort` mechanism (`opts[:effort]` of :low/:high/:none maps to the request body key `"reasoning_effort"`) and the provider default is `"low"`.

### generated tests: `for {name, {file, marker, effort}} <- @sources do test "#{name} runs at #{effort} effort" do ... end end`
(5 runtime tests with names "per-section beats runs at none effort", "the spine runs at high effort", "the weave runs at high effort", "the narratives runs at high effort", "the graph build runs at high effort". The grep count of 2 `test "` lines includes this one template.)
Body for each:
```elixir
source = File.read!(unquote(file))

# find the call that uses this prompt, and read the effort next to it
[_, after_marker] = String.split(source, unquote(marker) <> "}", parts: 2)
window = String.slice(after_marker, 0, 600)

case unquote(effort) do
  :high ->
    assert window =~ "effort: :high" or preceding_effort(source, unquote(marker)) == "high"

  :none ->
    assert preceding_effort(source, unquote(marker)) == "none"
end
```
(i.e. the source must contain the text `<marker>}` (e.g. `@beats_prompt}`, an interpolation of the prompt module attribute into a message), and either within the next 600 characters `effort: :high`, or the last `effort: :<word>` found before that text equals the expected one.)
Helper:
```elixir
# the effort flag sits above the messages list, so look backwards from the
# prompt reference to the nearest one
defp preceding_effort(source, marker) do
  case String.split(source, marker <> "}", parts: 2) do
    [before, _] ->
      case Regex.scan(~r/effort: :(\w+)/, before) do
        [] -> nil
        matches -> matches |> List.last() |> List.last()
      end
    _ -> nil
  end
end
```
(1 static assertion per branch; 1 executed per runtime test.)

Behavior not obvious from the code:
- Required efforts: per-section beats pass = `:none` (lib comment, analysis.ex: "Across three sections, high effort spent 7,860 reasoning tokens per ..."); spine = `:high`; weave = `:high`; narratives = `:high`; graph build = `:high`. The default for every other call is `"low"` (`reasoning_effort`). `llm.ex` treats effort `:none`/"none" specially (line 170).
- In lib the `:high` call sites are analysis.ex:364 (spine), weave.ex:119, decision_graph.ex:283 and :383; the `:none` is analysis.ex:207.

Assertion count: 2 + 1 static in the template per branch (2 branches) = 4 static, 7 executed (2 + 5).

---

## test/marginalia/document_test.exs  (8 tests; covers Marginalia.Document validate/3, current?/1, get/1, fingerprint/1, run/1; Marginalia.Summary.fingerprint/1; Works.DocumentSummary)

Module `Marginalia.DocumentTest`, `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Document, Summary, Works}`. Moduledoc: "The whole document, read two ways. What is tested here is the checking and the staleness, not the prose: a citation to a section that does not exist reads exactly like one that is true, and is the failure a reader cannot catch without going and looking." No LLM call is made anywhere (no put_env; run/1 is only exercised on its refusal path).

`setup`:
```elixir
user = user_fixture()

body =
  Enum.map_join(1..3, "\n\n", fn i ->
    "# Part #{i}\n\nSection #{i} body. " <> String.duplicate("word ", 300)
  end)

{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
%{work: work, sections: Works.list_sections(work.id)}
```
(three `# Part i` headings each with ~300 words give sections with ordinals 1, 2, 3; the tests assume exactly 3 sections, since citations to 14, 99 and 40 are "not sections here".)

Helper:
```elixir
defp summarise_all(sections) do
  Enum.map(sections, fn s ->
    {:ok, s} =
      s
      |> Ecto.Changeset.change(
        summary: "What section #{s.ordinal} does.",
        summary_fingerprint: Summary.fingerprint(s),
        summary_body: s.body
      )
      |> Repo.update()

    s
  end)
end
```
(Note it returns the original `s` as passed in, not the updated one; section schema has fields `summary`, `summary_fingerprint`, `summary_body`; `Summary.fingerprint(section)` is a function of the section.)

### describe "validate/3"
`Document.validate(comp, guide, sections)` takes the composition map (string keys: "summary", "throughline", "movements") , the guide map ("guidelines", "tensions"), and the section list; returns `{attrs, dropped}` where `attrs` is a map with atom keys (`.movements`, `.guidelines`, `.tensions`, ...) holding lists of string-keyed maps, and `dropped` is a list of human-readable reason strings.

#### test "a citation to a real section is kept"
```elixir
comp = %{
  "summary" => "It does a thing.",
  "throughline" => "One thread.",
  "movements" => [%{"heading" => "H", "sections" => [1, 2], "does" => "D"}]
}

{attrs, dropped} = Document.validate(comp, %{}, sections)
```
- assert [%{"sections" => [1, 2]}] = attrs.movements
- assert dropped == []
(2)

#### test "a citation to a section that does not exist is dropped and named"
```elixir
comp = %{
  "summary" => "s",
  "throughline" => "t",
  "movements" => [%{"heading" => "H", "sections" => [1, 14], "does" => "D"}]
}

{attrs, dropped} = Document.validate(comp, %{}, sections)
```
- assert [%{"sections" => [1]}] = attrs.movements
- assert [reason] = dropped
- assert reason =~ "14"
- assert reason =~ "not sections here"
(4)

#### test "guidelines and tensions are checked the same way"
```elixir
guide = %{
  "guidelines" => [%{"guideline" => "G", "because" => "B", "sections" => [2, 99]}],
  "tensions" => [%{"tension" => "T", "sections" => [40]}]
}

{attrs, dropped} = Document.validate(%{}, guide, sections)
```
- assert [%{"sections" => [2]}] = attrs.guidelines
- assert [%{"sections" => []}] = attrs.tensions   (a tension whose every citation is invalid is KEPT with an empty list)
- assert length(dropped) == 2
(3)

#### test "no tensions is a real answer and not an error"
```elixir
{attrs, dropped} = Document.validate(%{}, %{"guidelines" => [], "tensions" => []}, sections)
```
- assert attrs.tensions == []
- assert dropped == []
(2)

### describe "staleness"

#### test "a document with no summary is not current"  (`%{work: work}`)
- refute Document.current?(work)
- assert Document.get(work.id) == nil
(2)

#### test "the fingerprint is over the section summaries"  (`%{sections: sections}`)
```elixir
summarised = summarise_all(sections)
a = Document.fingerprint(summarised)
```
- assert a == Document.fingerprint(summarised)   (deterministic)
- comment "re-summarised: same text, different words for it": `reworded = List.update_at(summarised, 0, &%{&1 | summary: "Different words."})`; refute a == Document.fingerprint(reworded)
- comment "edited: same summary, different text under it": `edited = List.update_at(summarised, 0, &%{&1 | body: &1.body <> " and more."})`; refute a == Document.fingerprint(edited)
(3)  `Document.fingerprint/1` takes a list of section structs, using each one's `summary` and `body`.

#### test "editing a section makes the document summary stale"  (`%{work: work, sections: sections}`)
```elixir
summarised = summarise_all(sections)

{:ok, _} =
  %Marginalia.Works.DocumentSummary{}
  |> Marginalia.Works.DocumentSummary.changeset(%{
    work_id: work.id,
    summary: "The whole thing.",
    fingerprint: Document.fingerprint(summarised)
  })
  |> Repo.insert()
```
- assert Document.current?(work)
```elixir
first = hd(summarised)

block =
  first.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "Section 1"))

{:ok, _} = Works.replace_block(first, block, String.replace(block, "Section 1", "AMENDED"))
```
- refute Document.current?(Repo.reload!(work)), "a document summary built on a section that has since changed is out of date"
(2)

### test "a work with no sections is refused before any call"  (`%{work: work}`)
```elixir
Repo.delete_all(from s in Marginalia.Works.Section, where: s.work_id == ^work.id)
```
- assert Document.run(Repo.reload!(work)) == {:error, :no_sections}
(1)

Behavior not obvious from the code:
- Invalid citations are removed silently from the model's output but reported in `dropped`, each reason naming the bad number(s) and saying they are "not sections here". A tension left with no valid sections is kept (empty `sections`), while the dropped list gets an entry for each item that lost citations (2 here: one guideline, one tension).
- `current?/1` is false when no DocumentSummary row exists; true when the stored fingerprint equals the fingerprint of the current section summaries/bodies; editing a section's text via replace_block changes the section so it becomes false even if the section summary text did not change (the fingerprint covers both summary and body). `Repo.reload!(work)` is needed since `current?` reads from the work struct passed in (as tested).
- `Document.run/1` returns `{:error, :no_sections}` without making any LLM call when the work has no sections.

Assertion count: 19 (static).

---

## test/marginalia/editing_test.exs  (8 tests; covers Works.replace_block/3, Works.get_node/2, Works.get_work!/2, Works.list_sections/1)

Module `Marginalia.EditingTest`, `use Marginalia.DataCase, async: true`, alias `Marginalia.Works`, `import Marginalia.AccountsFixtures`. Moduledoc: "The draft is editable, and everything in the app is anchored into it. The interesting case is not saving text -- it is what happens to the notes that were about the line you changed."

`setup`:
```elixir
user = user_fixture()

body =
  "# A draft\n\nShe stood at the window for an hour.\n\n" <>
    "The kettle went cold on the counter.\n\n" <> String.duplicate("word ", 300)

{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
section = hd(Works.list_sections(work.id))

{:ok, kettle} =
  Works.insert_node(%{
    work_id: work.id,
    section_id: section.id,
    node_type: "beat",
    title: "The kettle",
    quote: "The kettle went cold on the counter."
  })

{:ok, window} =
  Works.insert_node(%{
    work_id: work.id,
    section_id: section.id,
    node_type: "beat",
    title: "The window",
    quote: "She stood at the window for an hour."
  })

%{work: work, section: section, kettle: kettle, window: window}
```
New nodes have status "pending" (asserted below).

### test "an edit lands in the section and in the work"  (`%{work: work, section: section}`)
```elixir
{:ok, %{section: updated}} =
  Works.replace_block(section, "The kettle went cold on the counter.", "The kettle went stone cold.")
```
- assert updated.body =~ "stone cold"
- refute updated.body =~ "went cold on the counter"
- comment "the work's body is the sections joined back up": assert Works.get_work!(work.user_id, work.id).body =~ "stone cold"
(3)

### test "a note about the line you changed is superseded, not deleted"  (`%{work: work, section: section, kettle: kettle, window: window}`)
```elixir
{:ok, %{superseded: n}} =
  Works.replace_block(section, "The kettle went cold on the counter.", "The kettle went stone cold.")
```
- assert n == 1
- assert Works.get_node(work.id, kettle.id).status == "superseded"
- assert Works.get_node(work.id, kettle.id).title == "The kettle", "it is kept, not thrown away"
- comment "a note about a line you did not touch is untouched": assert Works.get_node(work.id, window.id).status == "pending"
(4)

### test "a note still anchored after the edit survives it"  (`%{work: work, section: section, kettle: k}`)
Comment: "the quoted sentence is still there, with words added around it"
```elixir
{:ok, %{superseded: n}} =
  Works.replace_block(
    section,
    "The kettle went cold on the counter.",
    "Nobody moved. The kettle went cold on the counter."
  )
```
- assert n == 0
- assert Works.get_node(work.id, k.id).status == "pending"
(2)

### test "section boundaries do not move"  (`%{work: work, section: section}`)
```elixir
before = length(Works.list_sections(work.id))
{:ok, _} = Works.replace_block(section, "She stood at the window for an hour.", "She stood there.")
```
- assert length(Works.list_sections(work.id)) == before
- assert hd(Works.list_sections(work.id)).id == section.id
(2)

### test "emptying a paragraph is refused"  (`%{section: section}`)
- assert {:error, :empty} = Works.replace_block(section, "The kettle went cold on the counter.", "   ")
(1)

### test "an edit against a paragraph that has moved is refused"  (`%{section: section}`)
- assert {:error, :moved} = Works.replace_block(section, "a paragraph that is not there", "new")
(1)

### test "saving an unchanged paragraph does nothing"  (`%{section: section}`)
```elixir
block = "The kettle went cold on the counter."
```
- assert {:ok, %{superseded: 0}} = Works.replace_block(section, block, block)
(1)

### test "the word count follows the edit"  (`%{work: work, section: section}`)
```elixir
{:ok, %{section: updated}} =
  Works.replace_block(section, "She stood at the window for an hour.", "She stood.")
```
- assert updated.word_count < section.word_count
- assert Works.get_work!(work.user_id, work.id).word_count < work.word_count
(2)

Behavior not obvious from the code:
- `Works.replace_block(section, old_block_text, new_block_text)` replaces one paragraph block (found by exact text within the section body); returns `{:ok, %{section: updated_section, superseded: n}}` or `{:error, :empty}` (new text blank) or `{:error, :moved}` (old text not found in the section body).
- Supersede rule: a node whose quote no longer anchors (via Anchor.verify) in the edited section body becomes status "superseded" (kept, title unchanged, not deleted); a node still anchored (here: quote still verbatim in the new text) stays "pending", and unrelated nodes are untouched.
- Replacing a block does not renumber or split sections. Section and work `word_count` are recomputed; `work.body` is the sections rejoined (`get_work!(user_id, work_id)` signature).
- Replacing a block with an identical block is a no-op that still returns `{:ok, %{superseded: 0}}`.

Assertion count: 16 (static).

---

## test/marginalia/cuts_test.exs  (19 tests; covers Marginalia.Cuts locate/2, validate/2, members/2, open_folder_reading/2,3, list_cuts/1, content_sha/1, current?/2; Folders.create_folder/2, Folders.move_work/3; Cuts.Cut.result_changeset/2)

Module `Marginalia.CutsTest`, moduledoc "Addressing passages across drafts, and what survives validation.", `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Cuts, Folders, Works}`. No LLM call is made; the validator and member builders are pure/DB.

`setup` (every test, top level): `user = user_fixture()`; returns `%{user: user, other: user_fixture()}`.

Helper `draft/3`:
```elixir
defp draft(user, title, extra \\ "") do
  body =
    "# #{title}\n\nThe first paragraph of #{title}, which is long enough to stand alone.\n\n" <>
      "A second paragraph. #{extra}\n\n" <> String.duplicate("word ", 120)

  {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
  w
end
```
(works are created at the top level, not in a folder; `Works.create_work/2` with string keys.)

### describe "locating a quote"
`@hay "A Blimp closure can see its caller's locals. `eval.zig` has a test\nthat says so outright, and tail call elimination is written around it."` (a real newline between "test" and "that"; backticks around eval.zig). `Cuts.locate(quote, haystack)` returns the matching text from the haystack (string) or nil/false.

#### test "an exact quote comes back unchanged"
- assert Cuts.locate("A Blimp closure", @hay) == "A Blimp closure"
(1)

#### test "a re-wrapped quote is found anyway"
Comment: "the model joins the line break; the passage still contains it"
- assert found = Cuts.locate("has a test that says so outright", @hay)
- assert String.contains?(found, "\n")
- assert String.contains?(@hay, found)
(3)

#### test "what comes back is the draft's wording, not the model's"
```elixir
found = Cuts.locate("has a test that says so outright", @hay)
```
- refute found == "has a test that says so outright"
(1)

#### test "a fabricated quote is not found"
- refute Cuts.locate("A Blimp closure cannot see anything", @hay)
(1)

#### test "reordered words are not found"
- refute Cuts.locate("locals caller's its see", @hay)
(1)

#### test "blank is not found"
- refute Cuts.locate("   \n ", @hay)
(1)

### describe "keeping only what can be checked"
Comment: "These exist because the validator was private, nothing exercised it, and a rename from "document" to "member" silently dropped every claim on every folder while the theses still looked fine."

`setup`:
```elixir
members = [
  %{
    n: 1,
    kind: "work",
    id: 10,
    label: "Opinion",
    text: "The court held that standing\nwas absent from the start."
  },
  %{
    n: 2,
    kind: "work",
    id: 11,
    label: "Dissent",
    text: "Standing was plainly present, and the majority says otherwise."
  }
]

%{members: members}
```
Helper (module-level defp placed inside the describe):
```elixir
defp thread(evidence),
  do: %{"threads" => [%{"claim" => "They disagree.", "evidence" => evidence}]}
```
`Cuts.validate(raw_model_json, members)` returns `{result, dropped}`: `result` has atom keys (`.threads`, `.tensions`) holding lists of string-keyed maps; evidence items are enriched with `"label"`, `"id"`, and `"quote"` replaced by the member's own wording; `dropped` is a list of reason strings.

#### test "a claim with two locatable quotes survives"
```elixir
raw =
  thread([
    %{"member" => 1, "quote" => "standing was absent"},
    %{"member" => 2, "quote" => "Standing was plainly present"}
  ])

{result, dropped} = Cuts.validate(raw, members)
```
- assert dropped == []
- assert [%{"claim" => "They disagree.", "evidence" => evidence}] = result.threads
- assert Enum.map(evidence, & &1["label"]) == ["Opinion", "Dissent"]
- assert Enum.map(evidence, & &1["id"]) == [10, 11]
(4)

#### test "the stored quote is the member's wording, not the model's"
Comment: "the source has a line break in it; the model quotes across it"
```elixir
raw =
  thread([
    %{"member" => 1, "quote" => "held that standing was absent"},
    %{"member" => 2, "quote" => "Standing was plainly present"}
  ])

{result, []} = Cuts.validate(raw, members)
[first, _] = hd(result.threads)["evidence"]
```
- assert String.contains?(first["quote"], "\n")
(1; plus the match `{result, []}` requiring no drops)

#### test "a fabricated quote takes the claim down with it"
```elixir
raw =
  thread([
    %{"member" => 1, "quote" => "standing was absent"},
    %{"member" => 2, "quote" => "the court never reached the question"}
  ])

{result, dropped} = Cuts.validate(raw, members)
```
- assert result.threads == []
- assert Enum.any?(dropped, &String.contains?(&1, "quote is not in member 2"))
- assert Enum.any?(dropped, &String.contains?(&1, "needs 2"))
(3)

#### test "a claim resting on one member is not a finding about the group"
```elixir
raw = thread([%{"member" => 1, "quote" => "standing was absent"}])
{result, dropped} = Cuts.validate(raw, members)
```
- assert result.threads == []
- assert Enum.any?(dropped, &String.contains?(&1, "1 verifiable citation"))
(2)

#### test "a member number that is not in the group is refused"
```elixir
raw =
  thread([
    %{"member" => 1, "quote" => "standing was absent"},
    %{"member" => 7, "quote" => "standing was absent"}
  ])

{_result, dropped} = Cuts.validate(raw, members)
```
- assert Enum.any?(dropped, &String.contains?(&1, "member 7 is not in this group"))
(1)

#### test "the older key name still parses, so a prompt tweak cannot silently void everything"
```elixir
raw =
  thread([
    %{"document" => 1, "quote" => "standing was absent"},
    %{"document" => 2, "quote" => "Standing was plainly present"}
  ])

{result, dropped} = Cuts.validate(raw, members)
```
- assert dropped == []
- assert length(result.threads) == 1
(2)

#### test "tensions are checked exactly as threads are"
```elixir
raw = %{
  "tensions" => [
    %{
      "claim" => "One says the opposite of the other.",
      "evidence" => [
        %{"member" => 1, "quote" => "standing was absent"},
        %{"member" => 2, "quote" => "made this up entirely"}
      ]
    }
  ]
}

{result, dropped} = Cuts.validate(raw, members)
```
- assert result.tensions == []
- assert dropped != []
(2)

### describe "reading a folder"
(no describe-level setup; uses top-level `%{user:, other:}`)

#### test "a leaf folder is read over its drafts"  (`%{user: user}`)
```elixir
{:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
a = draft(user, "Opinion")
b = draft(user, "Dissent")
for w <- [a, b], do: {:ok, _} = Folders.move_work(user.id, w.id, f.id)

members = Cuts.members(user.id, f.id)
```
- assert length(members) == 2
- assert Enum.map(members, & &1.kind) == ["work", "work"]
- assert Enum.map(members, & &1.n) == [1, 2]
- assert Enum.all?(members, &(&1.text != ""))
(4)

#### test "a folder of folders is read over its children, not their drafts"  (`%{user: user}`)
```elixir
{:ok, top} = Folders.create_folder(user.id, %{name: "Cases"})
{:ok, one} = Folders.create_folder(user.id, %{name: "Case one", parent_id: top.id})
{:ok, two} = Folders.create_folder(user.id, %{name: "Case two", parent_id: top.id})
{:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, one.id)
{:ok, _} = Folders.move_work(user.id, draft(user, "Dissent").id, two.id)

members = Cuts.members(user.id, top.id)
```
- assert Enum.map(members, & &1.kind) == ["folder", "folder"]
- assert Enum.map(members, & &1.label) == ["Case one", "Case two"]
- comment: "neither child has been read, and the text says so rather than pretending": assert Enum.all?(members, &String.contains?(&1.text, "not read yet"))
- refute Enum.any?(members, & &1.read?)
(4)

#### test "a read child contributes its reading, not its drafts"  (`%{user: user}`)
```elixir
{:ok, top} = Folders.create_folder(user.id, %{name: "Cases"})
{:ok, one} = Folders.create_folder(user.id, %{name: "Case one", parent_id: top.id})
{:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, one.id)

{:ok, cut} = Cuts.open_folder_reading(user.id, one.id)

{:ok, _} =
  cut
  |> Marginalia.Cuts.Cut.result_changeset(%{
    status: "read",
    thesis: "The court split on standing.",
    threads: [%{"claim" => "Both turn on the same footnote."}]
  })
  |> Marginalia.Repo.update()

[member] = Cuts.members(user.id, top.id)
```
- assert member.read?
- assert member.text =~ "The court split on standing."
- assert member.text =~ "Both turn on the same footnote."
(3)

#### test "a folder has one reading, and re-opening replaces it"  (`%{user: user}`)
```elixir
{:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
{:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, f.id)

{:ok, first} = Cuts.open_folder_reading(user.id, f.id, "why?")
{:ok, again} = Cuts.open_folder_reading(user.id, f.id, "why really?")
```
- assert first.id == again.id
- assert again.question == "why really?"
- assert length(Cuts.list_cuts(user.id)) == 1
(3)

#### test "another writer's folder cannot be read"  (`%{user: user, other: other}`)
```elixir
{:ok, theirs} = Folders.create_folder(other.id, %{name: "Theirs"})
```
- assert {:error, :not_found} = Cuts.open_folder_reading(user.id, theirs.id)
(1)

#### test "a reading is stale once the folder holds something else"  (`%{user: user}`)
```elixir
{:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
{:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, f.id)
{:ok, cut} = Cuts.open_folder_reading(user.id, f.id)

{:ok, cut} =
  cut
  |> Marginalia.Cuts.Cut.result_changeset(%{
    status: "read",
    content_sha: Cuts.content_sha(Cuts.members(user.id, f.id))
  })
  |> Marginalia.Repo.update()
```
- assert Cuts.current?(cut, user.id)
```elixir
{:ok, _} = Folders.move_work(user.id, draft(user, "Late arrival").id, f.id)
```
- refute Cuts.current?(cut, user.id)
(2)

Behavior not obvious from the code:
- `Cuts.locate` folds whitespace (a quote with a space matches a source with "\n") and returns the SOURCE's own text, so the stored quote contains the newline; word order and words must match exactly (fabricated, reordered and blank return a falsy value).
- `Cuts.validate` rules, via dropped-reason substrings: "quote is not in member N" for an unlocatable quote; "member N is not in this group" for an unknown member number; "needs 2" (a claim needs at least 2 verifiable citations) and "1 verifiable citation" (reports how many survived). Any claim with fewer than 2 verifiable citations is removed from the result entirely; one fabricated quote therefore takes a two-quote claim down.
- Evidence key may be `"member"` or the older `"document"`; either parses. Tensions follow the same rules as threads.
- `Cuts.members(user_id, folder_id)` numbering `n` starts at 1. A leaf folder (holding works) gives `kind: "work"` members from its drafts; a folder whose children are folders gives `kind: "folder"` members, labelled with the child's name, with text containing "not read yet" and `read?: false` until the child's own reading exists; once the child has a Cut with status "read", the member text includes its `thesis` and each thread's `"claim"` and `read?` is true.
- `open_folder_reading` is one-per-folder (upsert): re-opening returns the same Cut id with the new `question`; `list_cuts(user_id)` stays at 1. A folder owned by another user gives `{:error, :not_found}`.
- Staleness: `current?(cut, user_id)` compares the cut's stored `content_sha` to `content_sha(members)`; moving another draft into the folder changes it. Tests set `content_sha` explicitly via `Cut.result_changeset/2` (fields used: status, thesis, threads, content_sha; and `question` on the struct).

Assertion count: 40 (static).

---

## test/marginalia/clusters_test.exs  (6 tests; covers Marginalia.Links get_or_create/2, clusters/1; Works.set_status/2)

Module `Marginalia.ClustersTest`, moduledoc "Links are pairs; pairs chain. This is the grouping that makes a chain visible, and the gap in it findable.", `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Links, Works}`.

`setup`:
```elixir
user = user_fixture()

make = fn title ->
  body =
    "# #{title}\n\nA sentence long enough for a section.\n\n" <>
      String.duplicate("word ", 200)

  {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
  {:ok, w} = Works.set_status(w, "read")
  w
end

%{
  user: user,
  one: make.("One"),
  two: make.("Two"),
  three: make.("Three"),
  far: make.("Unrelated")
}
```
Works are not in folders. `Links.get_or_create(work_id_a, work_id_b)` returns `{:ok, link}`. `Links.clusters(user_id)` returns a list of cluster maps `%{works: [work], links: [link], missing: [{work, work}]}` sorted biggest first.

### test "a chain of three is one group, not three pairs"  (`%{user: u, one: a, two: b, three: c}`)
```elixir
{:ok, _} = Links.get_or_create(a.id, b.id)
{:ok, _} = Links.get_or_create(b.id, c.id)
```
- assert [cluster] = Links.clusters(u.id)
- assert Enum.map(cluster.works, & &1.title) |> Enum.sort() == ["Three", "Two", "One"] |> Enum.sort()
- assert length(cluster.links) == 2
(3)

### test "the pair nobody has related yet is named"  (`%{user: u, one: a, two: b, three: c}`)
Comment: "1<->2 and 2<->3, so 1<->3 is the obvious next question and nothing else in the product would ever raise it" (original uses the arrow character U+2194)
```elixir
{:ok, _} = Links.get_or_create(a.id, b.id)
{:ok, _} = Links.get_or_create(b.id, c.id)

[cluster] = Links.clusters(u.id)
```
- assert [{x, y}] = cluster.missing
- assert Enum.sort([x.title, y.title]) == ["One", "Three"]
(2)

### test "once all three are related there is no gap left"  (`%{user: u, one: a, two: b, three: c}`)
Links: a-b, b-c, a-c.
- assert [%{missing: [], links: links}] = Links.clusters(u.id)
- assert length(links) == 3
(2)

### test "drafts that are not reachable from each other stay apart"  (`%{user: u, one: a, two: b, three: c, far: d}`)
Links: a-b, c-d.
```elixir
groups = Links.clusters(u.id)
```
- assert length(groups) == 2
- assert Enum.all?(groups, &(length(&1.works) == 2))
(2)

### test "the biggest group comes first, so the page leads with the real body of work"  (`%{user: u, one: a, two: b, three: c, far: d}`)
Links created in this order: c-d, then a-b, then b-c (so the 4-chain a-b-c-d forms only after the third call).
- assert [big | _] = Links.clusters(u.id)
- assert length(big.works) == 4
(2)

### test "one writer's constellations never include another's"  (`%{user: u, one: a, two: b}`)
```elixir
{:ok, _} = Links.get_or_create(a.id, b.id)

theirs = user_fixture()

{:ok, x} = Works.create_work(theirs.id, %{"title" => "X", "body" => String.duplicate("word ", 300)})
{:ok, y} = Works.create_work(theirs.id, %{"title" => "Y", "body" => String.duplicate("word ", 300)})

{:ok, _} = Links.get_or_create(x.id, y.id)
```
- assert [%{works: works}] = Links.clusters(u.id)   (u has exactly one cluster; the other user's X-Y link does not appear)
- refute Enum.any?(works, &(&1.title in ["X", "Y"]))
(2)  (X and Y are not set to status "read"; they have no heading.)

Behavior not obvious from the code:
- Clusters are connected components of the link graph (union over pairs). `missing` lists pairs inside a cluster with no direct link (for a 3-chain, the two ends; a complete triangle has none). `links` are the direct pair links inside the cluster. Groups sort by number of works descending.
- Clusters are scoped to the user's own works.
- `Links.get_or_create` is idempotent per pair, and the setup puts works in status "read" (the other user's works are left at the default status).

Assertion count: 13 (static).

---

TOTALS: static assertion counts recorded (assert/refute calls as written in source; comprehensions and helpers counted once, as noted per file):

| file | tests (grep -c '^\s*test "') | tests at runtime | assertions |
|---|---|---|---|
| test/marginalia/segmenter_test.exs | 13 | 13 | 32 |
| test/marginalia/sentences_test.exs | 28 | 28 | 31 |
| test/marginalia/sentences_works_test.exs | 11 | 11 | 24 |
| test/marginalia/reflow_test.exs | 12 | 12 | 27 |
| test/marginalia/diff_test.exs | 10 | 10 | 21 |
| test/marginalia/selection_test.exs | 16 | 16 | 14 (11 direct + 3 in roundtrip/1 helper) |
| test/marginalia/markdown_test.exs | 2 | 2 | 4 |
| test/marginalia/anchor_test.exs | 11 | 11 | 14 |
| test/marginalia/kinship_test.exs | 8 | 8 | 14 |
| test/marginalia/outline_test.exs | 5 | 5 | 10 |
| test/marginalia/editor_tools_test.exs | 8 | 8 | 16 |
| test/marginalia/beat_density_test.exs | 5 | 5 | 12 |
| test/marginalia/effort_test.exs | 2 | 6 (1 named + 5 generated from the template) | 4 |
| test/marginalia/document_test.exs | 8 | 8 | 19 |
| test/marginalia/editing_test.exs | 8 | 8 | 16 |
| test/marginalia/cuts_test.exs | 19 | 19 | 40 |
| test/marginalia/clusters_test.exs | 6 | 6 | 13 |
| TOTAL | 172 | 176 | 311 |

(Runtime total counts effort_test as 6; the other 16 files sum to 170 at runtime, so 176 total.)

LLM stubbing in this part: none. No file uses Application.put_env, FakeHub or any provider stub. Editor tools (run_call), Document.run (refusal path only), Cuts.validate and Analysis.thin/beat_* are exercised directly with inline data. effort_test reads lib source files from the repo root.

# PART 2. Imports, links, folders, summaries

# Part B: test/marginalia acceptance notes

All paths relative to test/marginalia/. "keep(rows, q)" below is the file-local helper defined in import_query_test.

## import_query_test.exs  (31 tests; covers Marginalia.Import.Query: filter/2, date/1, date/2, expand/1, hint/1)

Module: `use ExUnit.Case, async: true`, `alias Marginalia.Import.Query`. No DB, no LLM, pure functions.

Moduledoc (quoted, it is the reason for the file): "Two things here are worth more than the rest. An unknown qualifier has to be an error — a typo that silently means nothing lets somebody import a hundred and forty-seven pull requests believing they filtered to nine. And a missing date has to fail a comparison rather than sort before everything, or `merged:>2020-01-01` quietly sweeps in every pull request that was never merged at all."

Helpers:
- `pr(attrs)` = Map.merge of this default map with attrs (atom keys):
  `%{repo: "phoenixframework/phoenix", number: 100, title: "A change", state: "merged", draft: false, base: "main", head: "topic", created_at: "2025-01-01T00:00:00Z", updated_at: "2025-02-01T00:00:00Z", merged_at: "2025-02-01T00:00:00Z"}`
- `keep(rows, q)`: `assert {:ok, kept} = Query.filter(rows, q)` then returns `Enum.map(kept, & &1.number)` (so filter/2 returns `{:ok, [rows]}` preserving input order, and rows are the same maps). That is one assertion inside every keep call.

### describe "the shape people actually type"
setup (runs per test): today = Date.utc_today(); recent = today-3 days as ISO8601 date string ("YYYY-MM-DD", no time); old = today-200 days. rows:
1. `pr(%{number: 1, state: "closed", created_at: recent, title: "Fix the parser"})`
2. `pr(%{number: 2, state: "open", created_at: recent, title: "Bump eslint"})`
3. `pr(%{number: 3, state: "closed", created_at: old, title: "Old and closed"})`
4. `pr(%{number: 4, state: "merged", created_at: recent, title: "Merged lately"})`
Note created_at here is a bare date, whereas the default pr has a full datetime; both forms must compare as dates.

### test "is:pr state:closed created:>@today-30d"
- `keep(rows, "is:pr state:closed created:>@today-30d") == [1]` (1 assert)

### test "a bare word is the title, and a minus takes it away"
- `keep(rows, "fix") == [1]` (case-insensitive substring on title: "Fix the parser")
- `keep(rows, "-bump") == [1, 3, 4]` (2 asserts)

### test "terms are joined with and"
- `keep(rows, "state:closed created:>@today-30d -fix") == []` (1)

### test "an empty query keeps everything"
- `keep(rows, "") == [1, 2, 3, 4]`
- `keep(rows, "   ") == [1, 2, 3, 4]` (2)

### describe "an unknown qualifier"
### test "is refused by name rather than ignored"
- `assert {:error, why} = Query.filter([pr(%{})], "stat:closed")`; `why =~ "stat"`; `why =~ "do not know"` (3)

### test "the message lists what it does know"
- `{:error, why} = Query.filter([], "author:me")` (plain match, not an assert); `why =~ "created"`; `why =~ "merged"` (2)

### test "a bad value for a known qualifier says what the values are"
- `{:error, why} = Query.filter([], "state:draft")`; `why =~ "open, closed or merged"` (1)

### test "is:issue is refused, because there are none here"
- `assert {:error, why} = Query.filter([], "is:issue")`; `why =~ "only pull requests"` (2)

### test "is:pr is accepted and does nothing"
- rows = [pr(%{number: 7})]; `keep(rows, "is:pr") == [7]` (1)

### describe "dates"
### test "@today and its offsets"
today = Date.utc_today(). `Query.date/1` returns `{:ok, %Date{}}`:
- `Query.date("@today") == {:ok, today}`
- `Query.date("@today-30d") == {:ok, Date.add(today, -30)}`
- `Query.date("@today-2w") == {:ok, Date.add(today, -14)}`
- `Query.date("@today+7d") == {:ok, Date.add(today, 7)}` (4)

### test "a month offset is calendar months, clamped to a real day"
`Query.date/2` takes a second argument, the "today" to use:
- `Query.date("@today-1m", ~D[2025-03-31]) == {:ok, ~D[2025-02-28]}`
- `Query.date("@today-6m", ~D[2025-08-05]) == {:ok, ~D[2025-02-05]}`
- `Query.date("@today-1y", ~D[2025-08-05]) == {:ok, ~D[2024-08-05]}` (3)

### test "an absolute date, and something that is not one"
- `Query.date("2025-08-05") == {:ok, ~D[2025-08-05]}`
- `Query.date("last tuesday") == :error`
- `Query.date("@today-3fortnights") == :error` (3)

### test "a date that will not parse is named in the error"
- `assert {:error, why} = Query.filter([], "created:>yesterday")`; `why =~ "yesterday"`; `why =~ "@today-30d"` (the error message includes an example of the syntax) (3)

### test "ranges, open at either end"
rows (merged_at only differs): number 1 merged_at "2025-03-01T00:00:00Z"; 2 "2025-06-01T00:00:00Z"; 3 "2025-09-01T00:00:00Z".
- `keep(rows, "merged:2025-04-01..2025-08-01") == [2]`
- `keep(rows, "merged:2025-04-01..*") == [2, 3]`
- `keep(rows, "merged:*..2025-04-01") == [1]`
- `keep(rows, "merged:2025-06-01") == [2]` (bare date = same day equality; row 2's datetime 2025-06-01T00:00:00Z matches) (4)

### test "a pull request that was never merged fails every merged comparison"
rows: `pr(%{number: 1, state: "open", merged_at: nil})`, `pr(%{number: 2, merged_at: "2025-06-01T00:00:00Z"})`. Comment: "the trap: nil is "not a date", not "before everything"".
- `keep(rows, "merged:>2020-01-01") == [2]`
- `keep(rows, "merged:<2030-01-01") == [2]`
- `keep(rows, "-merged:>2020-01-01") == [1]` (negation of a failed comparison keeps the nil row) (3)

### describe "the other qualifiers"
### test "state and is agree with each other"
rows: 1 state open; 2 state merged.
- `keep(rows, "is:open") == [1]`; `keep(rows, "state:open") == [1]`; `keep(rows, "is:merged") == [2]` (3)

### test "draft, both ways round"
rows: 1 draft true; 2 draft false.
- `"is:draft"` -> [1]; `"draft:true"` -> [1]; `"draft:false"` -> [2]; `"-is:draft"` -> [2] (4)

### test "repo, base and head are exact and case insensitive"
rows: 1 repo "phoenixframework/phoenix" base "main"; 2 repo "elixir-lang/elixir" base "v1.19".
- `keep(rows, "repo:PhoenixFramework/Phoenix") == [1]`
- `keep(rows, "base:v1.19") == [2]`
- `keep(rows, "repo:phoenix") == []` with message "a partial repo is not a repo" (3)

### test "number compares as a number, not as a string"
rows: numbers 9, 100, 1000 (all other fields default).
- `"number:>90"` -> [100, 1000]; `"number:9..100"` -> [9, 100]; `"number:1000"` -> [1000] (3)

### test "a quoted phrase is one term" (top level, not in describe)
rows: 1 title "add a precommit alias"; 2 "alias the precommit hook" (comment: "both words, not the phrase"); 3 "add a guide".
- `keep(rows, ~s("precommit alias")) == [1]` message "quoted, they have to be adjacent"
- `keep(rows, "precommit alias") == [1, 2]` message "unquoted, both words anywhere" (2)

### describe "expanding @today for GitHub"
`Query.expand/1` is string -> string, rewriting `@today[+-]Nu` tokens to ISO dates relative to Date.utc_today().
### test "the query from the report, which GitHub answers 422"
- `Query.expand("repo:phoenixframework/phoenix state:closed created:>@today-30d") == "repo:phoenixframework/phoenix state:closed created:>#{today-30 as ISO}"` (1)

### test "every unit, and more than one in a query"
d(n) = today+n days ISO8601.
- `Query.expand("created:>@today-7d merged:<@today") == "created:>#{d(-7)} merged:<#{d(0)}"`
- `Query.expand("@today-2w") == d(-14)`
- `Query.expand("@today+1d") == d(1)` (3)

### test "a range with both ends relative"
- `Query.expand("merged:@today-60d..@today-30d") == "merged:#{today-60}..#{today-30}"` (1)

### test "everything else is left exactly as it was"
for q in `"repo:phoenixframework/phoenix is:pr"`, `"created:>2025-08-05"`, `"label:\"needs review\" -Bump"`, `""`: `Query.expand(q) == q` (4 evaluations of one assert statement; 1 assert statement)

### test "something that looks like @today but is not is left alone"
Comment: "not a unit this understands; better to let GitHub say so than to mangle it into a date nobody asked for".
- `Query.expand("@today-3fortnights") =~ "@today-3fortnights"`
- `Query.expand("@todays") =~ "@today"` (2; note `=~` so the output merely contains it)

### describe "why nothing matched"
`Query.hint/1` returns nil or `%{was: query, try: query_with_>}`.
### test "a bare relative date is the trap, and it is named"
- `Query.hint("created:@today-90d") == %{was: "created:@today-90d", try: "created:>@today-90d"}` (exact map) (1)
### test "an absolute one too"
- `Query.hint("merged:2025-08-05").try == "merged:>2025-08-05"` (1)
### test "nothing to say about a query that already compares"
- `hint("created:>@today-90d") == nil`; `hint("created:>=2025-01-01") == nil`; `hint("created:<2025-01-01") == nil` (3)
### test "nothing to say about a range either"
- `hint("merged:2025-04-01..2025-08-05") == nil`; `hint("merged:@today-60d..@today-30d") == nil` (2)
### test "nothing to say when there is no date in it at all"
- `hint("state:closed -Bump") == nil`; `hint("") == nil` (2)
### test "the date is found among other terms"
- `Query.hint("is:pr state:closed created:@today-90d -Bump").try == "created:>@today-90d"` (1)

Behavior not obvious from the code:
- Unknown qualifier => `{:error, string}` naming the qualifier, containing "do not know", and listing known qualifiers (at least "created", "merged"). Bad state value message contains literal "open, closed or merged". `is:issue` message contains "only pull requests". `is:pr` is a no-op; `is:open/merged/draft` act as state/draft shortcuts.
- Missing (nil) date fails every comparison (>, <), including in a negated term, where it is kept.
- A bare word is a case-insensitive title substring; AND semantics across terms; quoted phrase must be adjacent; `-` negates a term (including qualifiers, `-is:draft`, `-merged:>...`).
- Dates may be bare "YYYY-MM-DD" or full ISO datetimes in rows. A bare date equals a day; `*` is open-ended; ranges inclusive in the cases shown.
- Month/year offsets clamp to month end (Mar 31 minus 1m = Feb 28).
- Pure ExUnit, async, no seams.

## bulk_links_test.exs  (14 tests; covers Marginalia.Links.Bulk: sheet/2, describe/1, validate/2, ineligible/1, run/2; plus Links.linkable/1)

Module: `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Folders, Links, Works}`, `Marginalia.Links.Bulk`.

Moduledoc: "Choosing which documents to relate, before paying to relate any. The stack of pull requests is 111 documents, which is 6,105 pairs. The triage is the whole feature; what is tested here is that it cannot propose a pair that does not exist, and that it does not quietly skip the documents it is not allowed to relate."

Setup (every test): `user = user_fixture()`; `{:ok, folder} = Folders.create_folder(user.id, %{"name" => "A series"})` (string keys); four works, i in 1..4:
`Works.create_work(user.id, %{"title" => "#{i}. Chapter #{i}", "body" => "# H#{i}\n\n" <> String.duplicate("word ", 300)})` then `{:ok, _} = Folders.move_work(user.id, w.id, folder.id)`. Context map: %{user, folder, works} (works are the structs returned by create_work, in creation order; NOT reloaded after move). `sheet(ctx)` = `Bulk.sheet(ctx.user.id, ctx.folder.id)`. No LLM involvement anywhere; run/2 only hits the two early-return error paths.

### describe "the sheet handed to the model"
### test "one numbered line per document in the folder"
- `length(sheet) == 4`
- `Enum.map(s, & &1.n) == [1, 2, 3, 4]`
- `Enum.map(s, & &1.work.title) == Enum.map(ctx.works, & &1.title)` (order = titles "1. Chapter 1".."4. Chapter 4"). (3)
Entries are maps/structs with at least `:n`, `:work` (a work with :title, :id), `:line`.

### test "a document with nothing written about it still gets a line"
- `Enum.all?(sheet(ctx), &(&1.line == ""))` (1) - no summaries, no steps => line is the empty string "".

### test "a section summary is used when there is one"
- w = first work; `section = hd(Works.list_sections(w.id))`; `section |> Ecto.Changeset.change(summary: "It establishes the doorway.") |> Repo.update()` returns {:ok, _}.
- `Bulk.describe(Repo.reload!(w)) == "It establishes the doorway."` (1). describe/1 takes a work struct and returns the string.

### test "a stack step beats a section summary, being the better description"
- Same section updated with summary "A summary.".
- `Repo.insert!(%Marginalia.Stacks.Step{folder_id: ctx.folder.id, work_id: w.id, ordinal: 1, capability: "The thing emits a file that runs."})`
- `Bulk.describe(Repo.reload!(w)) == "The thing emits a file that runs."` (1)

### describe "validate/2"
`Bulk.validate(model_json_map, sheet)` returns `%{pairs: [...], dropped: [strings], skipped: ...}`.
### test "a real pair is kept with its hypothesis"
- input `%{"pairs" => [%{"a" => 1, "b" => 4, "why" => "one sets up four", "expect" => "pays_off"}]}`
- `assert [%{why: "one sets up four", expect: "pays_off"} = pair] = out.pairs` (atom keys, expect remains the string "pays_off")
- `pair.a.id == hd(ctx.works).id`; `pair.b.id == List.last(ctx.works).id` (a and b are work structs resolved from sheet numbers)
- `out.dropped == []` (4)

### test "a document that is not in the folder is dropped and named"
- input `%{"pairs" => [%{"a" => 1, "b" => 140}]}`
- `out.pairs == []`; `assert [reason] = out.dropped`; `reason =~ "140"`; `reason =~ "not in this folder"` (4). Note: no "why"/"expect" keys in input; must not crash.

### test "a document paired with itself is refused"
- `%{"pairs" => [%{"a" => 2, "b" => 2}]}` -> `out.pairs == []`; `[reason] = out.dropped`; `reason =~ "itself"` (3)

### test "the same pair twice is only one pair"
- `%{"pairs" => [%{"a" => 1, "b" => 3}, %{"a" => 3, "b" => 1}]}` (reversed order counts as same)
- `length(out.pairs) == 1`; `[reason] = out.dropped`; `reason =~ "twice"` (3)

### test "what it chose not to propose is carried through"
- `Bulk.validate(%{"pairs" => [], "skipped" => "2 and 3 are adjacent."}, sheet)` -> `out.skipped == "2 and 3 are adjacent."` (1)

### describe "relating"
### test "an unread pair is reported by name, not skipped in silence"
- `[a, b | _] = ctx.works`; `[message] = Bulk.ineligible([%{a: a, b: b, why: "w", expect: "develops"}])` (one message per pair)
- `message =~ a.title`; `message =~ b.title`; `message =~ "has not been read"` (3). Works default to a status that is not "read".

### test "a pair is eligible only when BOTH sides have been read"
- `{:ok, a} = Works.set_status(a, "read")` (returns {:ok, work})
- `assert [one] = Bulk.ineligible([%{a: a, b: b, ...}])`; `one =~ b.title`; `refute one =~ "#{a.title} has not been read"` (so the message names the unread work "<title> has not been read" and does not name the read one with that phrase)
- `{:ok, b} = Works.set_status(b, "read")`; `Bulk.ineligible([...]) == []` (4)

### test "a folder with nothing in it says so rather than calling the model"
- `{:ok, empty} = Folders.create_folder(ctx.user.id, %{"name" => "Nothing here"})`; `Bulk.run(ctx.user.id, empty.id) == {:error, :empty_folder}` (1)

### test "somebody else's folder is not readable"
- `stranger = user_fixture()`; `Bulk.run(stranger.id, ctx.folder.id) == {:error, :no_folder}` (1)

### test "linkable/1 is what the real pass needs, and these are not it"
- `Links.linkable(ctx.user.id) == []` with message: "Linker.run/2 fails with :not_read without node maps, which is why the bulk pass reports unread halves instead of relating them" (1). I.e. freshly created, unread works with no node maps are not linkable.

Behavior not obvious from the code:
- Priority for the one-line description: stack step capability > section summary > "" (empty string).
- Validation never raises on missing keys; reports dropped reasons as strings containing the offending number, "not in this folder", "itself", "twice".
- Ownership check precedes anything: other user's folder id -> `{:error, :no_folder}`; empty folder -> `{:error, :empty_folder}`, both before any model call (no LLM seam used in this file).

## import_bulk_test.exs  (15 tests; covers Marginalia.Import.Bulk: land/3, explain/1, by_title/2)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Folders, Works}`, `Marginalia.Import.Bulk`. setup: `%{user: user_fixture()}`. No LLM.

Moduledoc: "Landing a pile of documents in a folder. The behaviour worth pinning down is what happens to the batch when one of it is bad, and what counts as already having something. A bulk import that rolls back thirty-nine good documents because the fortieth was empty is an import nobody uses twice, and one that has no idea it already ran doubles the folder every time somebody presses the button again."

Helper `doc(title, body \\ nil)` = `%{title: title, body: body || "# #{title}\n\n" <> String.duplicate("word ", 80), source_url: nil}`.
`Bulk.land(user_id, docs, opts)` returns a map `%{created: [works], failed: [{title, reason}], skipped: [titles], folder: folder | nil}`. Opts: `folder: "name"`, `number: true`, `on_item: fn title, i, total -> ... end`.

### test "each document becomes a draft in the folder"
- `out = Bulk.land(user.id, [doc("One"), doc("Two")], folder: "Pile")`
- `length(out.created) == 2`; `out.failed == []`; `out.skipped == []`; `out.folder.name == "Pile"`
- titles = `user.id |> Works.list_works() |> Enum.map(& &1.title) |> Enum.sort()` == `["One", "Two"]`
- `Enum.all?(Works.list_works(user.id), &(&1.folder_id == out.folder.id))` (6)

### test "running it twice does not double the folder"
- land [One, Two] in "Pile"; again = land [One, Two, Three] in "Pile".
- `length(again.created) == 1`; `Enum.sort(again.skipped) == ["One", "Two"]`; `length(Works.list_works(user.id)) == 3` (3). Skipping is by title within the folder.

### test "the same title in a different folder is a different document"
- land [One] in "Pile"; other = land [One] in "Other pile".
- `length(other.created) == 1`; `length(Works.list_works(user.id)) == 2` (2)

### test "one bad document does not take the batch with it"
- docs `[doc("Good"), doc("Empty", "   "), doc("Also good")]` in "Pile"
- `length(out.created) == 2`; `assert [{"Empty", reason}] = out.failed`; `Bulk.explain(reason) =~ "no text"` (3). Reason is an opaque term passed to explain/1.

### test "an over-long document is named rather than swallowed"
- `huge = doc("Huge", String.duplicate("word ", 130_000))` (650,000 chars, 130,000 words); land [doc("Fine"), huge] in "Pile".
- `length(out.created) == 1`; `[{"Huge", reason}] = out.failed`; `Bulk.explain(reason) =~ "over the limit"` (3)

### test "titles are not numbered unless asked"
- land [Alpha, Beta] in "Plain"; `Enum.sort(titles) == ["Alpha", "Beta"]` (1)

### test "numbering follows the order given, and leaves an existing number alone"
- `Bulk.land(user.id, [doc("Alpha"), doc("2. Beta"), doc("Gamma")], number: true)` (no folder)
- `Enum.map(out.created, & &1.title) == ["1. Alpha", "2. Beta", "3. Gamma"]` (1). Position-based number; "2. Beta" already numbered is left as is.

### test "with no folder the drafts land loose"
- `out = Bulk.land(user.id, [doc("Loose")])` (two-arg form, opts default)
- `out.folder == nil`; `assert [work] = Works.list_works(user.id)`; `work.folder_id == nil` (3)

### test "an existing folder is reused, not duplicated"
- `{:ok, folder} = Folders.create_folder(user.id, %{name: "Mine"})` (atom keys here)
- land [One] with `folder: "Mine"`; `out.folder.id == folder.id`; `length(Folders.list_folders(user.id)) == 1` (2)

### test "progress is reported per document as it goes"
- `on_item: fn title, i, total -> send(me, {:landed, title, i, total}) end`, me = self() (callback runs in the calling process, synchronously)
- `assert_received {:landed, "One", 1, 2}`; `assert_received {:landed, "Two", 2, 2}` (2)

### describe "filtering by title"
Helper `cand(title)` = `%{repo: "a/b", number: 1, title: title}`. `Bulk.by_title(candidates, pattern)` returns `{:ok, kept}` or `{:error, binary}`.
### test "an empty pattern keeps everything"
- all = [cand("one"), cand("two")]; `Bulk.by_title(all, "") == {:ok, all}`; `Bulk.by_title(all, nil) == {:ok, all}` (2)
### test "it matches anywhere in the title, ignoring case"
- all = [cand("Fix the parser"), cand("Revert the fix"), cand("Add a test")]; `{:ok, kept} = by_title(all, "fix")`; titles == ["Fix the parser", "Revert the fix"] (2)
### test "it is a real regex"
- all = [cand("1. First"), cand("Later"), cand("2. Second")]; pattern `~S"^\d+\.")`; titles == ["1. First", "2. Second"] (2)
### test "a pattern that will not compile says so rather than raising"
- `assert {:error, why} = Bulk.by_title([cand("x")], "(unclosed")`; `is_binary(why)`; `why != ""` (3)
### test "a very long title cannot make the match run away"
Comment: "the subject is truncated, so a pattern that backtracks has 200 characters to do it in rather than a megabyte".
- long = cand(String.duplicate("a", 100_000) <> "needle"); `assert {:ok, []} = Bulk.by_title([long], "needle")` (1). So the title is truncated to ~200 chars before matching: a needle past the cutoff is NOT found.

Behavior not obvious from the code:
- land/3 is not all-or-nothing; each document succeeds or fails independently; failures are `{title, reason}` and reasons are rendered by `explain/1` (empty body -> text containing "no text"; too long (~130k words) -> text containing "over the limit").
- Idempotence by (folder, title): skipped list returns titles.
- Numbering only with `number: true`, 1-based position in the given list (including docs which already start with "N. ").
- Folder is found by name for the user, created if missing; folder: nil => works with folder_id nil and `out.folder == nil`.

## import_test.exs  (13 tests; covers Marginalia.Import: allowed/1, fetch/2)

Module: `use ExUnit.Case, async: true`; `alias Marginalia.Import`. No DB, no network (fetch is given `body:` so it never hits the network).

Moduledoc: "Reading a draft off the web: what gets refused, and what survives the trip from HTML to markdown."

### describe "what may be fetched"
### test "plain http and https to a public host"
- `assert {:ok, _} = Import.allowed("https://darioamodei.com/post/we-must-pace-the-frontier")`
- `assert {:ok, _} = Import.allowed("http://example.com/essay")` (2). Note these resolve a real public hostname in the original; a rewrite may need to avoid real DNS or accept it.

### test "nothing that is not http"
for url in `"file:///etc/passwd"`, `"ftp://example.com/x"`, `"gopher://example.com"`, `"javascript:alert(1)"`, `"data:text/html,hi"`: `assert {:error, :bad_scheme} = Import.allowed(url), "allowed #{url}"` (1 statement, 5 evaluations)

### test "nothing on this machine or this network"
Comment: "the server makes the request, from inside the network, with whatever the network trusts — so this is the boundary that matters". For each of:
`"http://localhost:4000/admin"`, `"http://127.0.0.1/"`, `"http://0.0.0.0/"`, `"http://10.0.0.5/"`, `"http://192.168.1.1/"`, `"http://172.16.4.4/"`, `"http://169.254.169.254/latest/meta-data/"`, `"http://[::1]/"`, `"http://something.local/"`, `"http://box.internal/"`
`assert {:error, :private_address} = Import.allowed(url), "allowed #{url}"` (1 statement, 10 evaluations)

### test "a hostname that resolves to loopback is still refused"
Comment: "the check cannot stop at the spelling of the host".
- `assert {:error, :private_address} = Import.allowed("http://localhost.localdomain/")` (1). Requires DNS resolution of the name (or a name-based rule) to detect loopback.

### test "rubbish is refused rather than crashing"
- `assert {:error, _} = Import.allowed("not a url")`
- `assert {:error, _} = Import.allowed("https://")`
- `assert {:error, :bad_url} = Import.allowed(nil)` (3)

### describe "turning a page into a draft"
Module attribute `@html` (heredoc, lines are indented by 4 in the source; heredoc strips that indentation):
```html
<html><head><title>Site name — An Essay</title>
<meta property="og:title" content="An Essay About Pacing" /></head>
<body>
  <nav><a href="/">Home</a><a href="/about">About</a></nav>
  <article>
    <h1>An Essay About Pacing</h1>
    <p>The <strong>first</strong> paragraph, with an <em>aside</em> and
       a <a href="https://example.com/x">link</a>.</p>
    <h2>Why Pace?</h2>
    <p>A second paragraph that is long enough to count for something at all.</p>
    <ul><li>One thing</li><li>Another thing</li></ul>
    <ol><li>First</li><li>Second</li></ol>
    <blockquote><p>Something someone said.</p></blockquote>
    <pre><code>defmodule A do
    end</code></pre>
    <p>A closing paragraph, also of a reasonable length for a test fixture,
       carrying enough words that the importer treats the page as an article
       rather than as a stub with nothing on it worth reading.</p>
    <p>One more paragraph so the fixture clears the floor the importer puts
       under a page before it will accept it as a draft at all, which exists
       so that a navigation-only page does not arrive as an empty manuscript.</p>
  </article>
  <footer><p>Subscribe to our newsletter for more!</p></footer>
  <script>console.log('tracking')</script>
</body></html>
```
(The `<pre><code>` line "end</code></pre>" is indented by 4 spaces relative to the heredoc margin, i.e. file text `        end</code></pre>` minus 4 = 4 spaces before `end`. Exactly: in the file the `<pre>` line begins at 8 spaces and `end` at 8 spaces; after stripping the 4-space heredoc margin, `<pre>` is at 4 spaces and `end</code></pre>` is at 4 spaces.)
`defp imported, do: Import.fetch("https://example.com/essay", body: @html)` -- `fetch(url, body: html)` uses the supplied HTML instead of fetching; returns `{:ok, %{title:, markdown:, url:}}` or `{:error, reason}`.

### test "the title comes from the page, not the tab"
- `assert {:ok, %{title: "An Essay About Pacing"}} = imported()` (1). (<title> is "Site name — An Essay"; og:title / h1 is used.)

### test "structure survives, because the segmenter cuts on headings"
markdown `md` contains: `"# An Essay About Pacing"`, `"## Why Pace?"`, `"- One thing"`, `"1. First"`, `"> Something someone said."`, and ```` "```" ```` (code fence). (6 `=~` asserts)

### test "inline markup survives"
`md =~ "**first**"`, `md =~ "*aside*"`, `md =~ "[link](https://example.com/x)"` (3)

### test "emphasis never wraps its own whitespace"
Comment: "`**text **` is not valid CommonMark and renders as four literal asterisks — this is the bug my own hand conversion shipped".
Body fed (heredoc, URL "https://example.com/e"):
```html
<article><h1>T</h1>
<p><strong>Verifiability. </strong>Embedded evaluators can check things.</p>
<20 repeats of: <p>Padding sentence for length.</p>>
</article>
```
(padding = `String.duplicate("<p>Padding sentence for length.</p>", 20)` interpolated on one line.)
- `md =~ "**Verifiability.** Embedded"` (trailing space moves outside the emphasis)
- comment: "the property that actually matters: `**text **` is not valid CommonMark and comes out as four literal asterisks on the page. `** ` on its own is fine — every closing delimiter is followed by one — so the test has to render it rather than grep for it."
- `{:safe, html} = Marginalia.Markdown.to_html(md)` (returns `{:safe, iodata/string}`; html is used with Regex.replace so must be a binary)
- `refute Regex.replace(~r/<[^>]+>/, html, "") =~ "*"` (no asterisk in tag-stripped text)
- `html =~ "<strong>Verifiability.</strong>"` (3 asserts)

### test "the furniture is left behind"
`refute md =~ "Subscribe to our newsletter"`; `refute md =~ "console.log"`; `refute md =~ "Home"` (3 refutes: footer, script and nav removed; note "Home" must not appear anywhere in the markdown)

### test "a page with no article in it is refused rather than imported empty"
- `assert {:error, :too_little_text} = Import.fetch("https://example.com/x", body: "<html><body><nav>Home</nav></body></html>")` (1)

### test "the source url comes back, so the draft can say where it is from"
- `assert {:ok, %{url: "https://example.com/essay"}} = imported()` (1)

### test "a refused address never reaches the fetch"
- `assert {:error, :private_address} = Import.fetch("http://169.254.169.254/latest/meta-data/", body: @html)` (1): the address check happens even when `body:` is provided.

Behavior not obvious from the code:
- allowed/1 returns `{:ok, _}` or `{:error, :bad_scheme | :private_address | :bad_url | other}`. nil -> :bad_url. Non-parsing/hostless strings -> some `{:error, _}`. Private ranges: loopback, 0.0.0.0, RFC1918 (10/8, 192.168/16, 172.16/12), link-local 169.254/16 (cloud metadata), IPv6 ::1, names ending `.local`/`.internal`, `localhost`, and names that resolve to loopback (`localhost.localdomain`).
- Minimum text floor => `:too_little_text`.
- Markdown must be CommonMark-valid: whitespace inside emphasis moves outside.

## links_test.exs  (24 tests; covers Marginalia.Links context: get_or_create/2, get_for/2, for_work/1, other/2, store_edges/3,4, edges/1, clear_edges/1, stats/1, plain/2, set_status/3, summary/1; and Marginalia.Analysis.Linker.types/0, prompt/0)

Module: `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, aliases `Marginalia.{Links, Works}`, `Marginalia.Analysis.Linker`. No LLM calls: edges are proposed as literal maps handed to `Links.store_edges`.

Moduledoc: "The linking graph, and the check that makes it worth reading. An edge between two manuscripts is a claim about both of them. The model proposes them by id, and this is where a proposal that cannot be true gets thrown away before anyone sees it."

### Top-level setup (every test)
`user = user_fixture()`. Local fn `make.(title, body)`:
1. `{:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})`
2. `{:ok, w} = Works.set_status(w, "read")` (returns {:ok, work})
3. `s = hd(Works.list_sections(w.id))` (the first section, produced by create_work segmenting on headings)
4. `{:ok, n} = Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in " <> title, quote: "a sentence"})`
5. returns `{w, n}`.
Three works:
- a: title "First", body `"# One\n\nA sentence that is long enough to be a section.\n\n" <> String.duplicate("word ", 200)`
- b: title "Second", body `"# Two\n\nAnother sentence that is long enough here.\n\n" <> String.duplicate("word ", 200)`
- c: title "Third", body `"# Three\n\nA third sentence, also long enough for this.\n\n" <> String.duplicate("word ", 200)`
Then `{:ok, link} = Links.get_or_create(a.id, b.id)`. Context: %{a, b, c, a_node, b_node, c_node, link} (link is a Links struct with id; no status set, so default).

### describe "the pair"
### test "is unordered — linking A to B is the same row as B to A"
- `assert {:ok, same} = Links.get_or_create(b.id, a.id)`; `same.id == link.id`; `Links.get_for(b.id, a.id).id == link.id` (3)

### test "a work cannot be linked to itself"
- `assert {:error, :same_work} = Links.get_or_create(a.id, a.id)` (1)

### test "it shows up from either side"
- `Links.for_work(a.id) |> Enum.map(& &1.id) == [link.id]`; same for `b.id` (2)

### test "the other side is named from whichever end you stand at"
- `link = Marginalia.Repo.preload(link, [:a_work, :b_work])` (association names :a_work, :b_work)
- `Links.other(link, a.id).id == b.id`; `Links.other(link, b.id).id == a.id` (2)

### describe "storing what the model proposed"
`Links.store_edges(link, proposed_list, allowed_types, cap \\ default)` returns `{kept_count, dropped_count}`. Proposed items are string-keyed maps `"from"`, `"to"` (node ids, int or string), `"type"`, `"why"`. `Linker.types()` is passed as the allowed-types list.

### test "a good edge is kept, with its reason"
- proposed: `[%{"from" => a_node.id, "to" => b_node.id, "type" => "answers", "why" => "It replies to the claim."}]`
- `assert {1, 0} = Links.store_edges(link, proposed, Linker.types())`
- `assert [edge] = Links.edges(link)`; `edge.edge_type == "answers"`; `edge.rationale == "It replies to the claim."`; `edge.from.id == a_node.id`; `edge.to.id == b_node.id` (edges/1 returns edges with :from and :to nodes preloaded) (6)

### test "an edge inside ONE manuscript is dropped"
- Comment: "the failure that would make the whole feature a lie: an internal edge presented as a relationship between the two documents".
- `{:ok, other} = Works.insert_node(%{work_id: a.id, node_type: "spine", title: "elsewhere in the same draft"})` (no section_id)
- proposed `[%{"from" => a_node.id, "to" => other.id, "type" => "develops", "why" => "Both in A."}]`
- `assert {0, 1} = Links.store_edges(...)`; `Links.edges(link) == []` (2)

### test "an invented id is dropped"
- from a_node.id, to `999_999`, type "develops", why "Points at nothing."; `assert {0, 1}` (1)

### test "an id from a third manuscript is dropped"
- from a_node.id, to c_node.id, type "develops", why "Reaches outside the pair."; `assert {0, 1}` (1)

### test "an unknown relation is dropped"
- from a_node, to b_node, type "vibes_with", why "Not a relation."; `assert {0, 1}` (1)

### test "an edge with no reason is dropped — the reason is the product"
- proposed: `[%{"from" => a_node.id, "to" => b_node.id, "type" => "develops", "why" => "   "}, %{"from" => b_node.id, "to" => a_node.id, "type" => "develops"}]` (whitespace-only why; missing why). Note the second edge goes b -> a (direction reversed).
- `assert {0, 2}` (1)

### test "string ids are accepted, because models return both"
- from `to_string(a_node.id)`, to `to_string(b_node.id)`, type "echoes", why "Same move."; `assert {1, 0}` (1)

### test "the same edge twice is stored once"
- e = `%{"from" => a_node.id, "to" => b_node.id, "type" => "develops", "why" => "Once."}`; `assert {1, 0} = Links.store_edges(link, [e, e], Linker.types())`; `length(Links.edges(link)) == 1` (2). Duplicate is counted as dropped (0 kept additional, 1 dropped).

### test "the edge count is capped"
- 80 extra nodes created on b: `Works.insert_node(%{work_id: b.id, node_type: "beat", title: "beat #{i}"})` for i in 1..80 (no section_id); proposal i: from a_node.id, to n.id, type "develops", why "Reason #{i}."
- `{kept, _} = Links.store_edges(link, extra, Linker.types(), 10)` (4th arg is the cap); `kept == 10`; `length(Links.edges(link)) == 10`; `assert b_node.id` (truthy; a no-op) (3)

### test "re-linking replaces rather than accumulates"
- store develops edge a->b ("First."); `Links.clear_edges(link)`; store tension edge a->b ("Second.")
- `assert [edge] = Links.edges(link)`; `edge.edge_type == "tension"` (2). Note after clear_edges, the same node pair can be stored again with another type.

### describe "the vocabulary"
### test "is the one a reader already knows, minus what cannot cross"
Comment: "`realises` and `asks_about` are about a node's place in its OWN document's spine, so they are meaningless between two".
- `refute "realises" in Linker.types()`; `refute "asks_about" in Linker.types()`
- `for t <- ~w(develops pays_off requires tension), do: assert(t in Linker.types())` (4 evaluations). Other types seen in this file: "answers", "echoes" (must be in the list).  (6 evaluations; 3 statements)

### test "every relation in the vocabulary is described in the prompt"
- `for t <- Linker.types(), do: assert(Linker.prompt() =~ t)` (1 statement, one per type)

### test "the prompt forbids the same-document edge in words, as well as in code"
- `assert Linker.prompt() =~ "one end in manuscript A and the other in manuscript B"` (1)

### describe "stats"
### test "count both the edges and how much of each side they touch"
- store one edge a_node -> b_node, type "answers", why "Because."; `s = Links.stats(link)`
- `s.edges == 1`; `s.by_type == %{"answers" => 1}`; `s.a_nodes == 1`; `s.b_nodes == 1` (4)

### describe "calling the documents by their names"
setup (additional, receives %{a, b}): comment "A numbered stack title, and one whose own text starts with "A " — between them they are every way this has gone wrong." 
- `{:ok, a} = Works.update_work(a, %{"title" => "1. A page with no script on it"})`
- `{:ok, b} = Works.update_work(b, %{"title" => "2. The backend scaffold"})`
- `{:ok, link} = Links.get_or_create(a.id, b.id)`; returns %{link: link}. (`Links.plain(text, link)` looks up the two works' CURRENT titles via the link; a is side A, b is side B.)

### test "a title beginning with a digit keeps its number"
- `out = Links.plain("runner. B answers it.", link)`
- Comment: "Built as `"\\1" <> "2. The backend scaffold"`, the replacement reads as backreference 12 — which does not exist, so it expanded to nothing and took the chapter number and the captured space with it."
- `assert out =~ "2. The backend scaffold"` (msg "the chapter number was eaten by a backreference nobody wrote")
- `refute out =~ "runner.. "` (msg "the captured whitespace went with it, doubling the full stop") (2)
  Implication: "B" after a sentence end ("runner. B answers") is a label and is replaced by the title, keeping the space.

### test "a title is never substituted into a second time"
- `out = Links.plain("B answers A's open question.", link)`
- Comment: "Six sequential replaces meant a title inserted early was ordinary English by the time a later pass read it, and "A page" inside it got substituted again. One pass resumes after the match it just made."
- `assert out == "2. The backend scaffold answers 1. A page with no script on it's open question."` (exact)
- `refute out =~ "1. 1."` (msg "the title was spliced through itself") (2)
  Note "A's" (possessive) becomes "<title A>'s": the apostrophe-s stays after the title.

### test "a possessive letter is resolved wherever it appears"
- `Links.plain("It sits downstream of A's grammar.", link)` `=~ "1. A page with no script on it's grammar"`
- Comment: "English has no possessive indefinite article, so "A's" is never the word "a" and needs no sentence-start to be safe." (1)

### test "the full form is resolved and loses the word Manuscript"
- `out = Links.plain("Manuscript B extends Manuscript A.", link)`
- `assert out == "2. The backend scaffold extends 1. A page with no script on it."` (exact; the final "." is the sentence period)
- `refute out =~ "Manuscript"` (2)

### test "a bare letter mid-sentence is left alone, and so is the article"
- Comment: ""Part A" is the reason this is not a plain word replacement, and "A page" is the reason it can never become one: telling the label from the article needs to know whether the next word is a verb."
- `assert Links.plain("See Part A and Exhibit B.", link) =~ "Part A and Exhibit B"` (unchanged)
- `refute Links.plain("It extends B.", link) =~ "2. The backend scaffold"` (msg "a bare letter mid-sentence could be anything") (2)

### test "the summary goes through the same substitution"
- `{:ok, link} = Links.set_status(link, "linked", %{summary: "B develops it. A is upstream."})` (3-arity: link, status string, attrs map)
- `Links.summary(link) =~ "2. The backend scaffold"`; `Links.summary(link) =~ "1. A page with no script on it"` (2). Sentence-start letters followed by verb ("B develops", "A is") are labels.

Behavior not obvious from the code:
- store_edges validation rules (each failure counts as dropped): endpoints must exist, one node in work A and one in work B (either direction accepted; edge direction kept as proposed), type must be in the allowed list, rationale non-blank (trimmed), exact duplicates collapsed, cap argument limits kept.
- ids may arrive as strings.
- Pair is stored unordered; `get_or_create` returns the same row either way; same-work returns `{:error, :same_work}`.
- `Links.plain/2` is a single-pass substitution of "A"/"B"/"Manuscript A|B" (and possessives "A's") with the work's title; a bare letter mid-sentence ("It extends B.", "Part A", "Exhibit B") stays; the digit-leading title must not be mangled by regex backreference semantics (title is inserted literally); the doubled-full-stop regression (`"runner.. "`) is guarded. Sentence start + letter followed by a verb counts as a label.

## link_chat_test.exs  (5 tests; covers Marginalia.Links.Chat (aliased LinkChat): card/1, prompt/0, absence of append/3, history/1, conversation/1; and Marginalia.Chat.Conversation.changeset/2)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Links, Works}`, `Marginalia.Links.Chat, as: LinkChat`, `Marginalia.Chat.Conversation`. No LLM calls.

Moduledoc: "The conversation about a pair: where it lives, and what it is handed."

### Setup (every test)
`user = user_fixture()`; fn `make.(title)`: body = `"# #{title}\n\nA sentence long enough to make a section of it.\n\n" <> String.duplicate("word ", 200)`; `Works.create_work(user.id, %{"title" => title, "body" => body})`; `Works.set_status(w, "read")`; `s = hd(Works.list_sections(w.id))`; `Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in #{title}", quote: "A sentence long enough"})`; returns {w, n}.
- `{a, an} = make.("First")`, `{b, bn} = make.("Second")`
- `{:ok, link} = Links.get_or_create(a.id, b.id)`; `{:ok, link} = Links.set_status(link, "linked", %{summary: "B answers A."})`
- `Links.store_edges(link, [%{"from" => an.id, "to" => bn.id, "type" => "tension", "why" => "They pull apart on pace."}], Marginalia.Analysis.Linker.types())`
- context %{link, a, b} (link is the struct returned by set_status, status "linked").

### describe "it is not kept"
### test "the module offers no way to store a turn"
Comment: "the turns live in the LiveView and die with it: this is a conversation about a shape, and the shape changes whenever either draft is re-read or the pair is linked again".
- `refute function_exported?(LinkChat, :append, 3)`; `refute function_exported?(LinkChat, :history, 1)`; `refute function_exported?(LinkChat, :conversation, 1)` (3). (Design constraint: no persistence API on Links.Chat.)

### test "and a conversation row still has to belong to a draft"
- `assert {:error, changeset} = %Conversation{} |> Conversation.changeset(%{}) |> Repo.insert()`
- `assert "can't be blank" in errors_on(changeset).work_id` (2). So Conversation requires work_id (error message verbatim "can't be blank"), changeset errors surfaced via errors_on.

### describe "what it is handed"
### test "both maps, every edge, and the reason each was drawn"
`card = LinkChat.card(link)` (a string). All `=~`:
- "First"; "Second"; "B answers A." (the link summary); "--tension-->" (edge rendering: `--<type>-->`); "They pull apart on pace." (rationale); and, comment "the anchored sentence travels with the node, so it can be quoted": "A sentence long enough" (the node's quote). (6)

### test "the sides are labelled, so it can tell which document is which"
- `card =~ "A:"`; `card =~ "B:"`; `card =~ "# MAP OF A"`; `card =~ "# MAP OF B"` (4)

### test "the prompt forbids the things the product does not do"
`p = LinkChat.prompt()`:
- `p =~ "do not write prose"`; `p =~ "do not rank them"`; comment "and the discipline that makes it worth reading": `p =~ "An edge you were not given does not exist"` (3)

Behavior not obvious from the code:
- Link chat is deliberately ephemeral: nothing in the Links.Chat API persists turns.
- Conversation changeset requires work_id.
- The card has both works' titles, link summary, each edge as `--type-->` with rationale, node quotes, and headers "A:", "B:", "# MAP OF A", "# MAP OF B".

## chat_modes_test.exs  (7 tests; covers Marginalia.Chat (create_conversation/1, set_mode/2, latest_conversation/1, append/3, history/1) and Marginalia.Chat.Editor (mode_names/0, default_mode/0, modes/0, mode/1))

Module: `use Marginalia.DataCase, async: true`; aliases `Marginalia.Chat`, `Marginalia.Chat.Editor`; `import Marginalia.AccountsFixtures`. No LLM calls.

Moduledoc: "Three stances over one set of tools. What changes between them is what the assistant is for; what never changes is that it will not write prose."

Setup (every test): `user = user_fixture()`; `{:ok, work} = Marginalia.Works.create_work(user.id, %{"title" => "W", "body" => String.duplicate("word ", 400)})`; context %{work: work}.

### test "there are three modes and read is the default"
- `Editor.mode_names() == ["read", "provoke", "bounce"]` (this order); `Editor.default_mode() == "read"` (2)

### test "each mode has its own opener and stance"
- for m <- Editor.modes(): `m.opener != ""`; `m.stance =~ "MODE:"` (2 statements, 3 iterations each). Modes are maps/structs with :id, :opener, :stance. (A trailing comment says "and they are actually different from each other" but nothing asserts it.)

### test "every mode still refuses to write the writer's prose"
Comment: "the shared system prompt carries the constraint; the stances must not quietly license their way around it".
- for m <- Editor.modes(): `refute m.stance =~ ~r/write (the|a|their) (next |new )?(scene|paragraph|sentence|line) for/i`
- `Editor.mode("provoke").stance =~ "never write prose"`
- `Editor.mode("bounce").stance =~ "not writing it for them"` (3 statements)

### test "an unknown mode falls back rather than crashing"
- `Editor.mode("nonsense").id == "read"`; `Editor.mode(nil).id == "read"` (2)

### test "a conversation remembers the stance it was held in"
- `{:ok, convo} = Chat.create_conversation(work.id)`; `convo.mode == "read"` (default mode stored)
- `{:ok, convo} = Chat.set_mode(convo, "bounce")`; `convo.mode == "bounce"`
- comment "reopening resumes it": `Chat.latest_conversation(work.id).mode == "bounce"` (3)

### test "switching stance keeps the history"
- create conversation; `Chat.append(convo.id, "user", "first question")` (return ignored); `{:ok, convo} = Chat.set_mode(convo, "provoke")`
- `assert [%{"content" => "first question"}] = Chat.history(convo.id)` (history returns a list of string-keyed maps; match is partial so also has "role" presumably); `convo.mode == "provoke"` (2)

### test "a junk mode cannot be stored on a conversation"
- `assert {:error, changeset} = Chat.set_mode(convo, "hacker")`; `assert %{mode: ["is invalid"]} = errors_on(changeset)` (2). Error text verbatim "is invalid".

Behavior not obvious from the code:
- Three modes only, in the order read, provoke, bounce; unknown/nil falls back to "read".
- Every stance must not license writing the writer's prose; provoke stance contains "never write prose"; bounce stance contains "not writing it for them"; every stance contains "MODE:".
- The mode is persisted on the conversation row with validation (inclusion) and switching mode does not touch messages.

## folders_test.exs  (17 tests; covers Marginalia.Folders context: tree/1, create_folder/2, move_work/3, move_folder/3, delete_folder/2, list_folders/1, backfill_from_collections/1; Works.get_work/2; Marginalia.Cases.place/3)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Folders, Works}`. No LLM.

Moduledoc: "Buckets of drafts: what may go where, and what survives a delete."

### Setup (every test)
`user = user_fixture()`; context `%{user: user, other: user_fixture()}`.

### Helpers
- `draft(user, title)`: body = `"# #{title}\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 60)`; `{:ok, work} = Works.create_work(user.id, %{"title" => title, "body" => body})` (string keys).
- `folder(user, name, parent \\ nil)`: `{:ok, f} = Folders.create_folder(user.id, %{name: name, parent_id: parent && parent.id})` (ATOM keys; parent_id nil for roots).
- Inside describe "backfilling folders from collections": `placed(user, title, collection, role)`: `w = draft(user, title)`; `{:ok, w} = Marginalia.Cases.place(w, collection, role)` (sets the work's collection name string and role string); returns w.

`Folders.tree(user_id)` returns `%{folders: [node], works: [work]}` for root; each node is `%{folder: folder, works: [work], folders: [node], count: integer}` (count includes everything below).

### test "a draft starts outside every folder and the tree says so"
- w = draft "Loose page"; `tree = Folders.tree(user.id)`; `tree.folders == []`; `assert [%{id: id}] = tree.works`; `id == w.id` (3)

### test "filing a draft moves it into the folder's node, not a copy of it"
- w "Loose page", f = folder "Case files"; `assert {:ok, _} = Folders.move_work(user.id, w.id, f.id)`; tree: `tree.works == []`; `assert [node] = tree.folders`; `node.folder.id == f.id`; `assert [%{id: id}] = node.works`; `id == w.id` (6)

### test "a folder's count includes what is buried below it"
- outer = folder "Outer"; inner = folder "Inner" with parent outer. Move drafts: "One" -> outer, "Two" -> inner, "Three" -> inner (each `{:ok, _} =`).
- `assert [node] = Folders.tree(user.id).folders`; `node.count == 3`; `assert [child] = node.folders`; `child.count == 2` (4)

### test "dropping a draft on the root unfiles it"
- w in f "Case files" first; `assert {:ok, _} = Folders.move_work(user.id, w.id, nil)`; `assert [%{id: id}] = Folders.tree(user.id).works`; `id == w.id` (3)

### test "a folder cannot be dropped into itself"
- `assert {:error, :cycle} = Folders.move_folder(user.id, f.id, f.id)` (1)

### test "a folder cannot be dropped into its own descendant"
- outer > inner > deeper (created via folder helper with parents).
- `assert {:error, :cycle} = Folders.move_folder(user.id, outer.id, deeper.id)`; comment "and the tree is unchanged by the refusal": `assert [node] = Folders.tree(user.id).folders`; `node.folder.id == outer.id` (3)

### test "two siblings may not share a name, but cousins may"
- outer = folder "Outer"; `_a = folder(user, "Notes", outer)`.
- `assert {:error, changeset} = Folders.create_folder(user.id, %{name: "Notes", parent_id: outer.id})`
- `assert "there is already a folder with that name here" in errors_on(changeset).name` (message verbatim; error is keyed on :name)
- comment "same name, different parent: fine": `assert {:ok, _} = Folders.create_folder(user.id, %{name: "Notes"})` (root-level "Notes") (3)

### test "deleting a folder keeps the drafts and lifts them one level"
- outer; inner (child of outer); w "Buried" moved into inner; grand = folder "Grandchild" under inner.
- `assert {:ok, _} = Folders.delete_folder(user.id, inner.id)`
- `assert Works.get_work(user.id, w.id)` (still exists); `assert [node] = Folders.tree(user.id).folders`; `node.folder.id == outer.id`; `assert [%{id: wid}] = node.works`; `wid == w.id` (work now in outer); `assert [child] = node.folders`; `child.folder.id == grand.id` (subfolder lifted to outer) (7)

### test "deleting a root folder drops its contents to the root"
- f "Case files", w "Filed" moved in; `assert {:ok, _} = Folders.delete_folder(user.id, f.id)`; tree: `tree.folders == []`; `assert [%{id: id}] = tree.works`; `id == w.id` (4)

### test "another writer's folder is not a place you can put anything"
- theirs = folder(other, "Theirs"); mine = folder(user, "Mine"); w = draft(user, "Mine too") moved into mine.
- comment "a forged parent lands the draft at the root rather than in their folder": `assert {:ok, moved} = Folders.move_work(user.id, w.id, theirs.id)`; `moved.folder_id == nil`
- `assert {:ok, moved_folder} = Folders.move_folder(user.id, mine.id, theirs.id)`; `moved_folder.parent_id == nil`
- comment "and their tree never saw any of it": `Folders.tree(other.id).works == []` (5). Note: forged target is NOT an error; it silently degrades to root.

### describe "backfilling folders from collections"
### test "each collection becomes a folder under one parent"
- placed(user, "Opinion", "Miller v. Alabama", "opinion"); placed(user, "Dissent", "Miller v. Alabama", "dissent"); placed(user, "Brief", "Dauch", "opinion"); `loose = draft(user, "A loose page")`.
- `assert {:ok, 3} = Folders.backfill_from_collections(user.id)` (3 = number of works filed)
- tree: comment "the uncollected draft is left at the root, not swept into a bucket": `assert [%{id: id}] = tree.works`; `id == loose.id`
- `assert [cases] = tree.folders`; `cases.folder.name == "Cases"`; `cases.count == 3`; `Enum.map(cases.folders, & &1.folder.name) == ["Dauch", "Miller v. Alabama"]` (alphabetical); `Enum.map(cases.folders, & &1.count) == [1, 2]` (8)

### test "running it twice files nothing the second time"
- placed one work; `assert {:ok, 1}` then `assert {:ok, 0}`; `length(Folders.list_folders(user.id)) == 2` ("Cases" + "Miller v. Alabama") (3)

### test "it reuses folders that are already there rather than failing on the name"
- `{:ok, cases} = Folders.create_folder(user.id, %{name: "Cases"})`; `{:ok, _} = Folders.create_folder(user.id, %{name: "Miller v. Alabama", parent_id: cases.id})`; placed Opinion in "Miller v. Alabama".
- `assert {:ok, 1}`; `length(Folders.list_folders(user.id)) == 2` (2)

### test "a draft the writer already filed is left where they put it"
- w placed in "Miller v. Alabama"; mine = create_folder "Reading pile"; move w into mine.
- `assert {:ok, 0}`; `Works.get_work(user.id, w.id).folder_id == mine.id` (2)

### test "with no collections anywhere it makes no folders at all"
- one loose draft; `assert {:ok, 0}`; `Folders.list_folders(user.id) == []` (2)

### test "it never reaches into another writer's drafts"
- placed(other, "Theirs", "Miller v. Alabama", "opinion"); placed(user, "Mine", "Miller v. Alabama", "dissent")
- `assert {:ok, 1} = Folders.backfill_from_collections(user.id)`; `Folders.list_folders(other.id) == []` (2)

### test "another writer's draft cannot be filed by me" (top level, last in file)
- theirs = draft(other, "Theirs"); mine = folder(user, "Mine")
- `assert {:error, :not_found} = Folders.move_work(user.id, theirs.id, mine.id)`
- `assert {:error, :not_found} = Folders.delete_folder(user.id, folder(other, "Nope").id)` (2)

Behavior not obvious from the code:
- Moving a draft/folder into someone else's folder id is silently treated as root (no error); but moving someone else's DRAFT, or deleting someone else's FOLDER, is `{:error, :not_found}`.
- Cycles (self or descendant) are `{:error, :cycle}` and leave the tree unchanged.
- Sibling-name uniqueness is per (user, parent), error text "there is already a folder with that name here" on :name; same name under different parents (incl. root) is fine.
- Deleting a folder lifts both its drafts and its subfolders to the deleted folder's parent (root if none); nothing is destroyed.
- Backfill: all collection names go under one root folder named "Cases", one subfolder per distinct collection name; only unfiled works with a collection are filed; return `{:ok, n_works_filed}`; idempotent; reuses existing "Cases" and child folders; scoped to the user.
- Tree ordering: folders sorted by name; counts are recursive.

## summary_test.exs  (19 tests; covers Marginalia.Summary: current?/1, fingerprint/1, run/1, spine/2, previous_block/2, validate/3, drift/1; Works.replace_block/3; Marginalia.Diff.words/2)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Repo, Summary, Works}`. LLM: none. `Summary.run/1` is only exercised on its pre-flight `{:error, :empty}` path; summaries are written straight onto the section row with `Ecto.Changeset.change |> Repo.update`.

Moduledoc: "A summary of a section, and knowing when it has stopped being true. A summary of prose that has since been rewritten is worse than none: it is a confident description of text that is not there."

### Setup (every test)
```elixir
user = user_fixture()
body =
  "# One\n\nALPHA the first paragraph. " <>
    String.duplicate("word ", 300) <> "\n\n# Two\n\nBRAVO. " <> String.duplicate("word ", 300)
{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
%{work: work, section: hd(Works.list_sections(work.id))}
```
Two sections ("One", "Two"), section = first. Sections have fields :title, :body, :summary, :summary_fingerprint, :summary_body, :summary_covers, :summary_follows, :summary_sets_up (the last three appear as keys of validate/3's output attrs).

### test "a section with no summary is not current"
- `refute Summary.current?(section)` (1)

### test "a stored summary is current against the text it was made from"
- `section |> Ecto.Changeset.change(summary: "It sets up alpha.", summary_fingerprint: Summary.fingerprint(section)) |> Repo.update()` -> `{:ok, section}`; `assert Summary.current?(section)` (1)

### test "editing the section makes its summary stale"
- Same update as above; `assert Summary.current?(section)`.
- block = `section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&String.contains?(&1, "ALPHA"))`
- `{:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))`
- `refute Summary.current?(Repo.reload!(section))` msg "a summary of prose that has been rewritten describes text that is not there"
- `assert Repo.reload!(section).summary == "It sets up alpha."` msg "the stale summary is kept and marked, not silently deleted"
- `assert work.id` (no-op) (4). replace_block(section, old_block_text, new_block_text) edits the section body (and must not clear summary).

### test "an empty section is refused before any call is made"
- `Summary.run(%{section | body: "   "}) == {:error, :empty}` (1) -- no LLM call because it returns before it. (Section map with whitespace body.)

### test "the fingerprint changes with the text and not with anything else"
- `a = Summary.fingerprint(section)`; `assert a == Summary.fingerprint(%{section | title: "A different title"})`; `refute a == Summary.fingerprint(%{section | body: section.body <> " more"})` (2). Fingerprint depends only on body.

### describe "the prompt knows where the section sits"
### test "the spine lists every section and marks this one"
- `siblings = Works.list_sections(work.id)`; `spine = Summary.spine(siblings, section)` (string)
- `spine =~ "1. One"`; `spine =~ "2. Two"`; `spine =~ "<- THIS ONE"`; `length(String.split(spine, "\n")) == length(siblings)` (one line per section, no trailing newline, so exactly 2 lines) (4)

### test "the section before is handed over in the words already used for it"
- `[first, second] = Works.list_sections(work.id)`; set first's `summary: "It establishes alpha."` (no fingerprint).
- `block = Summary.previous_block(Works.list_sections(work.id), second)`; `block =~ "It establishes alpha."`; `block =~ "1. One"` (2). Does not require the summary to be current.

### test "the first section has no previous block rather than an empty one"
- `Summary.previous_block(Works.list_sections(work.id), first) == ""` (1)

### test "an unsummarised predecessor contributes nothing"
- `Summary.previous_block(sections, second) == ""` when first has no summary (1)

### describe "validate/3"
Module attribute `@body "The out-grammar declares the syntax, and kcodegen expands it into Blimp.kt."`. `Summary.validate(model_output_map, section_body, section_index) :: {attrs_map, dropped_reasons_list}`; third arg is the 1-based position of this section (3 in most tests, 2 in the last two).
### test "a term that is really in the section is kept"
- input `%{"summary" => "It sets up the emitter.", "covers" => ["out-grammar", "kcodegen"]}`, @body, 3
- `attrs.summary_covers == ["out-grammar", "kcodegen"]`; `dropped == []` (2)

### test "a term the section never mentions is dropped and said so"
- `%{"summary" => "s", "covers" => ["out-grammar", "monad transformers"]}`, @body, 3
- `attrs.summary_covers == ["out-grammar"]`; `assert [reason] = dropped`; `reason =~ "monad transformers"`; `reason =~ "not in the section"` (4)

### test "matching ignores case, because prose capitalises at a sentence start"
- `{attrs, []} = Summary.validate(%{"summary" => "s", "covers" => ["Out-Grammar"]}, @body, 3)` (match requires dropped == [])
- `attrs.summary_covers == ["Out-Grammar"]` (original casing preserved) (1)

### test "follows_from only points backwards"
- `%{"summary" => "s", "covers" => [], "follows_from" => [1, 2, 5, 3]}`, @body, 3
- `attrs.summary_follows == [1, 2]`; `length(dropped) == 2` msg "5 and 3 are not earlier than 3" (2). Strictly less than own index; one dropped reason per bad number.

### test "an empty sets_up is nil rather than a blank line on the page"
- `%{"summary" => "s", "covers" => [], "sets_up" => "  "}`, @body, 2 -> `attrs.summary_sets_up == nil` (1)

### test "duplicates are collapsed and the list is bounded"
- `covers = ["kcodegen", "kcodegen"] ++ for(_ <- 1..10, do: "out-grammar")`; validate `%{"summary" => "s", "covers" => covers}`, @body, 2
- `attrs.summary_covers == ["kcodegen", "out-grammar"]` (1) (first-occurrence order; the bound itself is not exercised beyond dedup)

### describe "what moved under a stale summary"
setup (receives %{section}): updates section with `summary: "It sets up alpha."`, `summary_fingerprint: Summary.fingerprint(section)`, `summary_body: section.body` and returns `%{section: section}` (the updated one). `summary_body` is the source text the summary was made from, stored for diffing.

### test "a current summary has no drift to show"
- `Summary.drift(section) == []` (1)

### test "an edited section shows the paragraph that changed"
- block found as above (paragraph containing "ALPHA"); `Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))`
- `rows = Summary.drift(Repo.reload!(section))`; `assert Enum.any?(rows, &match?({:change, _, _}, &1))`
- `{:change, old, new} = Enum.find(rows, ...)`; `old =~ "ALPHA"`; `new =~ "AMENDED"` (3). Drift rows are tuples; `{:change, old_paragraph, new_paragraph}` is one kind (others exist, e.g. adds/removes, unasserted).

### test "the word diff marks what went and what arrived"
- same edit; `{:change, old, new}`; `parts = Marginalia.Diff.words(old, new)` (list of `{op, text}` with ops including :del, :ins)
- `assert Enum.any?(parts, fn {op, t} -> op == :del and t =~ "ALPHA" end)`; `assert Enum.any?(parts, fn {op, t} -> op == :ins and t =~ "AMENDED" end)` (2)

### test "a summary written before the source was kept draws no diff"
- section updated with `summary_body: nil, summary_fingerprint: "stale"`.
- `refute Summary.current?(section)`; `assert Summary.drift(section) == []` msg "inventing a baseline would draw a diff that never happened" (2)

Behavior not obvious from the code:
- Currency = stored `summary_fingerprint == fingerprint(body)`; no summary => not current; stale summaries stay on the row.
- run/1 guards on blank body before calling any model: `{:error, :empty}`.
- validate/3 drops covers terms not found (case-insensitive) in the body with reason text containing the term and "not in the section"; dedups; follows_from must be < own index; blank sets_up -> nil.
- drift/1: no baseline (`summary_body` nil) => `[]`, never invented.

## compare_summary_test.exs  (6 tests; covers Marginalia.Document.to_draft/2, Document.compare/2 (error path only), Marginalia.Works.condensation_of/1, Works.delete_work/1, Works.list_nodes/1, Marginalia.Links.get_or_create/2, Marginalia.Analysis.Linker.run/2)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Document, Links, Repo, Works}`.
LLM: none reached (moduledoc: "The model is not reached here. What is asserted is the ordering and the bookkeeping: that the condensation knows where it came from, that asking twice does not make two of them, and that the link is between the right pair."). The one test that calls `Linker.run(link, nil)` hits the guard `a_nodes == [] or b_nodes == []` -> `fail(link, :not_read)` before any model call (lib reading: run/2 sets status "linking", then returns via `fail/2` if either work has no nodes).

Moduledoc rationale: "The reason this is a comparison and not a replacement: a summary read on its own is a claim about a document you are no longer looking at. Held against the original, with the relations drawn between them, it is checkable — this paragraph is what those four became, and that promise in the long version has nothing answering it in the short one."

### Setup (every test)
```elixir
user = user_fixture()
body =
  "# One\n\nThe kettle went cold on the counter. " <>
    String.duplicate("word ", 90) <>
    "\n\n# Two\n\nNobody moved to fill it again. " <> String.duplicate("other ", 90)
{:ok, work} = Works.create_work(user.id, %{"title" => "The long version", "body" => body})
{:ok, work} = Works.set_status(work, "read")
for {s, i} <- Enum.with_index(Works.list_sections(work.id), 1) do
  s |> Ecto.Changeset.change(summary: "Section #{i}, in short.") |> Repo.update!()
end
%{user: user, work: work}
```
Both sections get summary "Section 1, in short." and "Section 2, in short." (no fingerprint, no covers, no sets_up). `work.status == "read"` but no nodes are inserted.

### test "the condensation is a draft of its own and says what it condenses"
- `assert {:ok, summary} = Document.to_draft(ctx.user.id, ctx.work)`
- `summary.id != ctx.work.id`; `summary.derived_from_id == ctx.work.id`; `summary.body =~ "Section 1, in short."`
- comment "and the original is untouched, which is the whole difference from replacing it": `Repo.reload(ctx.work).body =~ "The kettle went cold on the counter"` (4)

### test "the original is found from the condensation and back again"
- `Works.condensation_of(ctx.work.id).id == summary.id`; `Works.condensation_of(summary.id) == nil` (2)

### test "asking twice reuses the condensation rather than making a second"
- `{:ok, first} = Document.to_draft(...)`; comment "what `compare/3` does before it spends anything": `assert Works.condensation_of(ctx.work.id).id == first.id`
- `{:ok, again} = Document.to_draft(...)`; `assert again.id != first.id` msg "to_draft/2 on its own always makes one"
- comment "...and condensation_of takes the newest, so compare/3 never stacks up": `assert Works.condensation_of(ctx.work.id).id == again.id` (3)

### test "relating needs both sides read, and says so rather than guessing"
- `{:ok, summary} = Document.to_draft(...)`; `{:ok, link} = Links.get_or_create(ctx.work.id, summary.id)`
- comment "the condensation has no map yet: Linker refuses rather than inventing relations between a document and one nobody has read"
- `assert Works.list_nodes(summary.id) == []`
- `assert Marginalia.Analysis.Linker.run(link, nil)` (just truthy; returns something truthy such as `{:error, :not_read}`)
- `assert Repo.reload(link).status in ["failed", "linking"]` (3). Note the original work also has no nodes, so run fails on either side. Link status after a failed run is "failed" (the test tolerates "linking").

### test "a draft with nothing summarised cannot be compared"
- `{:ok, bare} = Works.create_work(ctx.user.id, %{"title" => "Nothing summarised", "body" => "# X\n\n" <> String.duplicate("word ", 90)})`
- `assert {:error, :nothing_summarised} = Document.compare(ctx.user.id, bare)`; `Works.condensation_of(bare.id) == nil` (2)

### test "deleting the long version leaves the condensation alone"
- `{:ok, summary} = Document.to_draft(...)`; `{:ok, _} = Works.delete_work(ctx.work)` (delete_work takes the work struct)
- `kept = Repo.reload(summary)`; `assert kept` msg "the condensation is somebody's draft now, not an appendix"; `assert kept.derived_from_id == nil` (2). The FK is nilified on delete (on_delete: :nilify_all), not cascaded.

Behavior not obvious from the code:
- `Document.to_draft(user_id, work)` always makes a new draft (field `derived_from_id` = source work id); `Works.condensation_of(work_id)` returns the NEWEST condensation of that work, nil for a work that is not a source.
- `Document.compare/2` returns `{:error, :nothing_summarised}` when no section has a summary and creates nothing.
- Deleting the source detaches (nil), never deletes, the condensation.

## summarise_folder_test.exs  (11 tests; covers Marginalia.Stacks.stats/2, Stacks.summarise_documents/2,3, Stacks.read_documents/2,3, Stacks.Step, Works.DocumentSummary, Links.get_or_create/2)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Folders, Repo, Stacks, Works}`, `Marginalia.Works.DocumentSummary`. LLM: none ("Nothing here reaches the model"; every test is either a stats query or a pass that has nothing to do and returns before calling).

Moduledoc rationale: "Summarising every document in a folder. Nothing here reaches the model. What is worth pinning down is which documents the pass would *skip*, because that is the difference between re-reading a hundred and eleven imported pull requests and reading the four that arrived since — and it is decided before a single call is made."

### Setup (every test)
`user = user_fixture()`; `{:ok, folder} = Folders.create_folder(user.id, %{name: "Imported"})`; `make.(title)`: `Works.create_work(user.id, %{"title" => title, "body" => "# #{title}\n\n" <> String.duplicate("word ", 90)})` then `Folders.move_work(user.id, w.id, folder.id)`; returns the work struct (created before the move, so its folder_id field is stale). Context: `%{user, folder, a: make.("1. One"), b: make.("2. Two"), c: make.("3. Three")}`. Works are NOT set to "read" (default status).
Helper `summarised(work, text \\ "what it says")` = `Repo.insert!(%DocumentSummary{work_id: work.id, summary: text, fingerprint: "f"})`.
`Stacks.stats(user_id, folder_id)` returns a map with keys: `:documents`, `:summarised`, `:related`, `:read`, `:mapped` (at least).

### test "the count is part of the folder's stats"
- `Stacks.stats(ctx.user.id, ctx.folder.id).summarised == 0`
- summarised(a); summarised(b); `stats.documents == 3`; `stats.summarised == 2` (3)

### test "a row with an empty summary does not count as summarised"
- `summarised(ctx.a, "")`; `Stacks.stats(...).summarised == 0` (1)

### test "a folder already summarised does nothing and calls nobody"
- `for w <- [a, b, c], do: summarised(w)`; `me = self()`
- `assert {0, []} = Stacks.summarise_documents(ctx.user.id, ctx.folder.id, on_step: fn w, i, t -> send(me, {:step, w.title, i, t}) end)` (return `{count_done, failures}`; opts keyword with `on_step` callback of arity 3)
- `refute_received {:step, _, _, _}` (2)

### test "an empty folder is not an error"
- `{:ok, empty} = Folders.create_folder(ctx.user.id, %{name: "Nothing in it"})`; `assert {0, []} = Stacks.summarise_documents(ctx.user.id, empty.id)` (2-arity, opts default) (1)

### test "another writer's folder yields nothing rather than their documents"
- `theirs = user_fixture()`; `assert {0, []} = Stacks.summarise_documents(theirs.id, ctx.folder.id)` (1)

### test "the count the page shows is what would actually be worked on"
- summarised(a); stats; comment "the button says "Summarise the other N", and N has to be the number the pass would really touch or the progress bar lies from the first tick"; `assert stats.documents - stats.summarised == 2` (1)

### describe "how many pairs of it are related"
### test "counts only pairs with both ends inside the folder"
- `Stacks.stats(...).related == 0`
- `{:ok, inside} = Marginalia.Links.get_or_create(ctx.a.id, ctx.b.id)`; `related == 1`
- comment "a link out of the folder is a real link and not this folder's business: counting it would make the number under the button move for something the button did not do": outside = `Works.create_work(ctx.user.id, %{"title" => "Elsewhere", "body" => "# E\n\n" <> String.duplicate("word ", 90)})` (loose, not in folder); `Links.get_or_create(ctx.a.id, outside.id)`; `related == 1` still. (`_ = inside` silences a warning.) (3). Note: link status is default (not "linked"); any link row between two folder works counts.

### test "an empty folder has none rather than raising"
- empty folder "Empty"; `Stacks.stats(ctx.user.id, empty.id).related == 0` (1)

### describe "reading each document"
### test "a folder whose documents are all mapped has nothing to do"
- `for w <- [a, b, c], do: Works.set_status(w, "read")` (status "read" = mapped); `assert {0, []} = Stacks.read_documents(ctx.user.id, ctx.folder.id, on_step: fn w, i, t -> send(me, {:step, w.title, i, t}) end)`; `refute_received {:step, _, _, _}` (2)

### test "mapped counts documents with a graph, not documents with a step"
- `stats.documents == 3`; `stats.mapped == 0`
- comment "a step is the forward read's output and says nothing about whether the document has a map of its own — the distinction that made relating a fully-stepped folder produce nothing"
- `Repo.insert!(%Stacks.Step{folder_id: ctx.folder.id, work_id: ctx.a.id, ordinal: 1, capability: "x"})`
- `assert stats.read == 1` msg "one step"; `assert stats.mapped == 0` msg "and still no map"
- `Works.set_status(ctx.a, "read")`; `Stacks.stats(...).mapped == 1` (5). So `:read` counts works with a Stacks.Step; `:mapped` counts works with status "read".

### test "another writer's folder reads nothing"
- `assert {0, []} = Stacks.read_documents(user_fixture().id, ctx.folder.id)` (1)

Behavior not obvious from the code:
- "summarised" counts DocumentSummary rows whose summary is a non-empty string (empty string does not count).
- `summarise_documents` and `read_documents` return `{n, errors}` tuples; with nothing to do or no ownership they return `{0, []}` without calling `on_step`.
- stats are scoped by ownership and folder; links counted only when both works are in the folder.

## summaries_to_draft_test.exs  (7 tests; covers Marginalia.Document.to_draft/2, Works.list_sections/1, Works.replace_block/3, Works.revision_count/1, Works.DocumentSummary)

Module: `use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; aliases `Marginalia.{Document, Summary, Works}`, `Marginalia.Works.DocumentSummary`. No LLM (summaries are written straight onto rows).

Moduledoc: "The summaries, as something to write from. Until now they could only be read where they were written, which makes them a report. A condensation you can edit and have read is a draft."

### Setup (every test)
```elixir
user = user_fixture()
body = Enum.map_join(1..3, "\n\n", fn i -> "# Part #{i}\n\nSection #{i} body. " <> String.duplicate("word ", 300) end)
{:ok, work} = Works.create_work(user.id, %{"title" => "The Quiet House", "body" => body})
%{user: user, work: work, sections: Works.list_sections(work.id)}
```
Three sections titled (per the tests' references) "Part 1".."Part 3".
Helper `summarise(section, text, opts \\ [])`: `section |> Ecto.Changeset.change(Keyword.merge([summary: text, summary_fingerprint: Summary.fingerprint(section), summary_body: section.body], opts)) |> Repo.update()` -> `{:ok, s}`, returns s. (opts may override e.g. `summary_covers`, `summary_sets_up`.)

### test "nothing summarised makes no draft"
- `assert Document.to_draft(ctx.user.id, ctx.work) == {:error, :nothing_summarised}`; `assert length(Works.list_works(ctx.user.id)) == 1` (2)

### test "each summarised section becomes a part of the new draft"
- each of 3 sections summarised with `"What section #{i} does, at length. " <> String.duplicate("word ", 280)` (i from 1)
- `{:ok, draft} = Document.to_draft(...)`; `draft.title == "The Quiet House — in summary"` (em dash U+2014 with spaces); `draft.body =~ "What section 1 does"`; `draft.body =~ "What section 3 does"`; `length(Works.list_sections(draft.id)) >= 2` (4)

### test "a section nobody summarised is left out rather than blank"
- only first section summarised with `"Only this one. " <> String.duplicate("word ", 280)`
- `draft.body =~ "Only this one."`; titles = `Works.list_sections(draft.id) |> Enum.map(& &1.title)`; `refute Enum.any?(titles, &(&1 =~ "2. Part 2"))` (so section titles in the draft are numbered "N. Part N", e.g. "1. Part 1"); `assert draft.intent =~ "1 of its 3 sections"` (the draft's `intent` field records coverage) (3)

### test "the covers and what it sets up ride along"
- first summarised with `"A summary. " <> String.duplicate("word ", 280)` plus `summary_covers: ["the out-grammar", "kcodegen"]`, `summary_sets_up: "a module that runs"`
- `draft.body =~ "It deals with: the out-grammar, kcodegen."`; `draft.body =~ "It leaves in place: a module that runs"` (2)

### test "the document summary opens it and the guidelines close it"
- first summarised ("A summary. " + 280 words); then
```elixir
Repo.insert!(%DocumentSummary{
  work_id: ctx.work.id,
  summary: "It builds a thing and then fixes what is underneath it.",
  throughline: "Nothing runs until the emitter is generated.",
  guidelines: [%{"guideline" => "Name the failing case first.", "because" => "It locates the fix."}]
})
```
- `draft.body =~ "It builds a thing and then fixes what is underneath it."`; `draft.body =~ "Nothing runs until the emitter is generated."`
- comment "the `##` itself is gone from the body: a work's body is the join of its sections and the segmenter lifts a heading into the section title": `draft.body =~ "Name the failing case first."`
- titles of draft sections: `assert Enum.any?(titles, &(&1 =~ "working under" or &1 =~ "Part 1"))` (loose; some section title contains "working under" (the guidelines heading, the guidelines heading is "What it is working under" per lib/marginalia/document.ex) or "Part 1") (4)

### test "it is not filed in the folder of the draft it condenses"
- `assert is_nil(draft.folder_id)` msg "a condensation in the folder it condenses becomes document N+1 of it" (1). (Note this test's work has no folder in setup, so the assertion is weak as written; the intent is that to_draft never copies/assigns the source's folder.)

### test "the new draft is an ordinary one: editable, with its own history"
- first summarised with "A summary worth editing. " + 280 words; draft = to_draft; `section = hd(Works.list_sections(draft.id))`; block = `section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "worth editing"))`
- `{:ok, _} = Works.replace_block(section, block, String.replace(block, "worth editing", "EDITED"))`
- `Works.revision_count(draft.id) == 1`; `Repo.reload!(draft).body =~ "EDITED"` (2). So creating the draft records no revision (count 0 before) and one edit makes exactly 1.

Behavior not obvious from the code:
- Draft body per summarised section: the section summary, "It deals with: <covers joined by ", ">." and "It leaves in place: <sets_up>" lines when present; document-level summary/throughline open the draft; guidelines close it; unsummarised sections omitted; title is "<title> — in summary"; `intent` mentions "N of its M sections".
- `Document.to_draft` returns `{:error, :nothing_summarised}` when no section summaries exist, and creates nothing.
- The result is an ordinary editable work with `derived_from_id` (see compare_summary_test), segmented into sections, no folder.

## TOTALS

Assertion counts are by grep of lines containing assert/refute/assert_received/refute_received (includes assertions inside helpers and `for` comprehensions, once per statement).

| file | tests | assertions |
|---|---|---|
| import_query_test | 31 | 69 |
| bulk_links_test | 14 | 31 |
| import_bulk_test | 15 | 36 |
| import_test | 13 | 27 |
| links_test | 24 | 48 |
| link_chat_test | 5 | 18 |
| chat_modes_test | 7 | 16 |
| folders_test | 17 | 61 |
| summary_test | 19 | 36 |
| compare_summary_test | 6 | 17 |
| summarise_folder_test | 11 | 21 |
| summaries_to_draft_test | 7 | 18 |

TOTALS: tests=169 assertions=398 (per file above)

# PART 3. Stacks, remote hosting, local repos, decision graph, walkthrough

# Part C1

LLM mechanism note for all nine files: none of them call an LLM, stub a provider, or put_env an API key. Every function under test is a pure validator/formatter or a DB/git function. The model's output is represented by hand-written "raw" maps (string keys) passed to validators.

"dropped" is a list of human-readable strings returned by validators; tests match substrings of those strings (`String.contains?` / `=~`).

---

## test/marginalia/stacks_test.exs  (26 tests; covers Marginalia.Stacks, Marginalia.Stacks.Step, Marginalia.Stacks.Story)

Module `Marginalia.StacksTest`, `use Marginalia.DataCase, async: true`, `import Marginalia.AccountsFixtures`, `alias Marginalia.{Folders, Stacks, Works}`.

Top-level `setup` (runs for every test, including those in describe blocks):
- `user = user_fixture()`
- `{:ok, folder} = Folders.create_folder(user.id, %{name: "A backend"})` (atom key `name:` here)
- context: `%{user: user, folder: folder}`

Helper `draft(user, title, body \\ nil)`: if body is nil, body is
`"# #{title}\n\nThe first paragraph of #{title}, long enough to stand alone.\n\n" <> "A second paragraph with something quotable in it.\n\n" <> String.duplicate("word ", 120)`.
Then `{:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})`, returns `w` (Work struct with `.id`, `.title`). Works are not filed in any folder by this helper.

### describe "the order a stack is read in"  (Stacks.order/1 takes a list of works)

### test "a leading number in every title is the author saying the order"
- works = [draft "3. Third", draft "1. First", draft "2. Second"] (created in that order).
- assert `Enum.map(Stacks.order(works), & &1.title) == ["1. First", "2. Second", "3. Third"]`
- Assertions: 1.

### test "numbers well past ten still sort as numbers"
- works = [draft "10. Tenth", draft "9. Ninth", draft "1. First"]
- assert `Enum.map(Stacks.order(works), &String.slice(&1.title, 0, 2)) == ["1.", "9.", "10"]`
- Assertions: 1.

### test "without numbers it is insertion order, which is the only other true thing"
- a = draft "Alpha" (created first), b = draft "Beta".
- assert `Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]` (input [b, a]; output in creation order).
- Assertions: 1.

### test "a half-numbered stack falls back rather than guessing"
- a = draft "1. First" (created first), b = draft "Untitled".
- assert `Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]`
- Assertions: 1.

### test "duplicate numbers fall back too"
- a = draft "1. First", b = draft "1. Also first".
- assert `Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]`
- Assertions: 1.

### describe "keeping only what the document says"
Module attribute (a single Elixir string; `\n` escapes are real newlines):
```
@body "Blimp has no variadic call.\n\nSo the fix has to be a list, packed at the call site\nand unpacked in the handler."
```
Paragraph 1: `Blimp has no variadic call.`; blank line; paragraph 2: `So the fix has to be a list, packed at the call site` NEWLINE `and unpacked in the handler.` (one hard newline mid-paragraph between "site" and "and"). The top-level setup still runs but these tests take no context.

Function: `Stacks.validate(raw, body, ordinal)` -> `{attrs, dropped}`; attrs has atom keys; ordinal is `5` in every call here (this document's position; `requires` must be < 5).

### test "a locatable pitfall quote is kept, with the document's own wording"
- raw:
```
%{
  "capability" => "a rest formal becomes one parameter holding a list",
  "requires" => [1],
  "lesson" => "Pack at the call site.",
  "pitfall" => "Do not try a variadic call.",
  "pitfall_quote" => "the fix has to be a list, packed at the call site and unpacked",
  "excerpts" => []
}
```
- `{attrs, dropped} = Stacks.validate(raw, @body, 5)`
- assert `dropped == []`
- assert `attrs.pitfall == "Do not try a variadic call."`
- (comment "re-wrapped on the way in, stored as the document has it") assert `String.contains?(attrs.pitfall_quote, "\n")`. The quote given has a space between "site" and "unpacked"; the document has newline plus "and". So quotes match whitespace-insensitively and the stored quote is the document's own text including its newline.
- Assertions: 3.

### test "a pitfall the document does not state is dropped, not softened"
- raw: `%{"pitfall" => "Blimp secretly supports varargs.", "pitfall_quote" => "Blimp secretly supports varargs.", "requires" => [], "excerpts" => []}`
- assert `attrs.pitfall == nil`
- assert any dropped string contains `"quote is not in the document"`.
- Assertions: 2.

### test "requires must name an earlier document"
- raw: `%{"requires" => [2, 5, 9, "x"], "excerpts" => []}`, ordinal 5.
- assert `attrs.requires == [2]`
- assert any dropped contains `"requires 5"`
- assert any dropped contains `"requires 9"`
- assert any dropped contains `"not a number"`
- Assertions: 4.

### test "an excerpt is the paragraph around the quote, from the document"
- raw: `%{"requires" => [], "excerpts" => [%{"quote" => "packed at the call site", "caption" => "the shape"}]}`
- `{attrs, []} = Stacks.validate(raw, @body, 5)` (dropped must be exactly `[]`)
- assert `[%{"caption" => "the shape", "text" => text}] = attrs.excerpts` (excerpt maps have STRING keys "caption" and "text")
- assert `String.contains?(text, "unpacked in the handler")` (whole paragraph containing the quote, including the part after the newline)
- assert `String.contains?(@body, text)` (verbatim substring of the document)
- Assertions: 3.

### test "an invented excerpt is dropped"
- raw excerpts: `[%{"quote" => "fn apply(args: List)", "caption" => "x"}]`, requires `[]`
- assert `attrs.excerpts == []`
- assert any dropped contains `"is not in the document"`
- Assertions: 2.

### test "at most two excerpts survive"
- raw excerpts: for each q in `["Blimp has no variadic", "packed at the call site", "unpacked in the handler"]` -> `%{"quote" => q, "caption" => "c"}`; all three locatable; requires `[]`.
- `{attrs, []} = Stacks.validate(...)` (dropped is `[]`; truncating to two is not reported)
- assert `length(attrs.excerpts) == 2`
- Assertions: 1.

### describe "the second pass, which can see forwards"
Comment (verbatim): "The forward pass is told only what came before each step, so it cannot say "step 9 walks this back". That claim is the one the second pass can make and the one that can do damage — it sends a reader off to read something that may not say that at all — so it has to name a later step and quote that step's own summary."

Describe-level `setup` (atom-key maps) gives context `%{later: later}`:
```
later = [
  %{ordinal: 8, capability: "holes type-check", lesson: "Emit a hole operator.", pitfall: nil},
  %{ordinal: 9, capability: "casts are checked",
    lesson: "Replace the unchecked cast with a real test.",
    pitfall: "The earlier cast compiled to nothing at all."}
]
```
Function: `Stacks.validate_deep(raw, later)` -> `{attrs, dropped}`.

### test "a revision naming a later step and quoting it is kept"
- raw:
```
%{"mechanism" => "It splits the body at the first exit and lifts the tail.",
  "watch_for" => "Step 9 leans on the cast being a real test.",
  "revised_by" => 9,
  "revision" => "Step 9 replaces the unchecked cast.",
  "revision_quote" => "Replace the unchecked cast with a real test."}
```
- assert `dropped == []`
- assert `attrs.revised_by == 9`
- assert `attrs.revision_quote == "Replace the unchecked cast with a real test."`
- assert `attrs.watch_for =~ "Step 9"`
- Assertions: 4.

### test "a revision pointing at a step that is not later is refused"
- raw: `%{"mechanism" => "x", "revised_by" => 3, "revision" => "Step 3 changed it.", "revision_quote" => "anything"}`
- assert `attrs.revised_by == nil`
- assert any dropped contains `"step 3 is not a later step"` (lowercase "step")
- Assertions: 2.

### test "a revision whose quote is not in that step's summary is refused"
- raw: `%{"mechanism" => "x", "revised_by" => 9, "revision" => "Step 9 deletes the whole translator.", "revision_quote" => "Step 9 deletes the whole translator."}`
- assert `attrs.revised_by == nil`
- assert `attrs.revision == nil`
- assert any dropped contains `"quote is not in step 9"`
- Assertions: 3.

### test "no revision is a normal answer"
- raw: `%{"mechanism" => "x", "watch_for" => "", "revised_by" => 0, "revision" => "", "revision_quote" => ""}`
- assert `attrs.revised_by == nil` (0 means none)
- assert `attrs.watch_for == nil` (empty string becomes nil)
- assert `dropped == []`
- Assertions: 3.

### test "an empty mechanism is the one thing this pass must not return"
- `Stacks.validate_deep(%{"revised_by" => 0}, later)`
- assert `attrs.mechanism == nil`
- assert any dropped contains `"mechanism"`
- Assertions: 2.

### test "the last step has nothing after it and that is fine"
- no context arg. raw: `%{"mechanism" => "x", "revised_by" => 4, "revision" => "later", "revision_quote" => "q"}`; later list is `[]`.
- assert `attrs.revised_by == nil`
- assert any dropped contains `"not a later step"`
- Assertions: 2.

### describe "composing the telling"
Comment (verbatim): "Prose is not quote-checkable the way a claim is, so the thing that can be checked is whether the composition actually carries every step. A telling that covers four of ten has thrown the method away, and it is the failure least likely to look like one."

Setup: `steps = for n <- 1..4, do: %Marginalia.Stacks.Step{ordinal: n, capability: "does #{n}"}` (unsaved structs); context `%{steps: steps}`.
Helper `part(heading, steps)` = `%{"heading" => heading, "prose" => "Some prose.", "steps" => steps, "turn" => ""}`.
Function: `Stacks.validate_story(raw, steps)` -> `{attrs, dropped, uncovered}`; `attrs.movements` is a list of string-keyed maps.

### test "a telling covering every step keeps all of it"
- raw: `%{"title" => "How it is built", "opening" => "op", "closing" => "cl", "movements" => [part("Groundwork", [1, 2]), part("The hard part", [3, 4])]}`
- assert `dropped == []`
- assert `uncovered == []`
- assert `Enum.map(attrs.movements, & &1["heading"]) == ["Groundwork", "The hard part"]`
- Assertions: 3.

### test "a step left out of every part is named, not waved through"
- raw: `%{"movements" => [part("Only the start", [1, 2])]}` (no title/opening/closing keys)
- `{_attrs, dropped, uncovered}`
- assert `uncovered == [3, 4]`
- assert any dropped contains `"appear in no part: 3, 4"`
- Assertions: 2.

### test "a step told twice is refused the second time"
- raw: `%{"movements" => [part("A", [1, 2]), part("B", [2, 3, 4])]}`
- assert `uncovered == []`
- assert any dropped contains `"step 2 is told twice"`
- assert `Enum.map(attrs.movements, & &1["steps"]) == [[1, 2], [3, 4]]`
- Assertions: 3.

### test "a step that is not in this stack is refused"
- raw: `%{"movements" => [part("A", [1, 2, 3, 4, 9])]}`
- assert any dropped contains `"step 9 is not in this stack"`
- Assertions: 1.

### test "parts are ordered by the work, not by what came back"
- raw: `%{"movements" => [part("Later", [3, 4]), part("Earlier", [1, 2])]}`
- `{attrs, [], []} = Stacks.validate_story(raw, steps)` (dropped and uncovered both `[]`)
- assert `Enum.map(attrs.movements, & &1["heading"]) == ["Earlier", "Later"]`
- Assertions: 1.

### test "a part with no prose is not a part"
- raw movements: `[%{"heading" => "Empty", "prose" => "  ", "steps" => [1, 2]}, part("Real", [3, 4])]` (first has no "turn" key; prose is two spaces)
- assert `length(attrs.movements) == 1`
- assert `uncovered == [1, 2]`
- assert any dropped contains `"no prose"`
- Assertions: 3.

### test "completeness is a property the story carries"
- refute `Marginalia.Stacks.Story.complete?(%Marginalia.Stacks.Story{uncovered: [3]})`
- assert `Marginalia.Stacks.Story.complete?(%Marginalia.Stacks.Story{uncovered: []})`
- Assertions: 2. (No DB use.)

### describe "the guide"  (DB; uses top-level setup user and folder)

### test "links run both ways, and the ends know they are ends"
- For each `{title, ord, req}` in `[{"1. One", 1, []}, {"2. Two", 2, [1]}, {"3. Three", 3, [1, 2]}]`:
  - `w = draft(user, title)`
  - `{:ok, _} = Folders.move_work(user.id, w.id, folder.id)`
  - `{:ok, _} = %Marginalia.Stacks.Step{} |> Marginalia.Stacks.Step.changeset(%{folder_id: folder.id, work_id: w.id, ordinal: ord, capability: "does thing #{ord}", requires: req}) |> Marginalia.Repo.insert()`
- `[one, two, three] = Stacks.guide(folder.id)` (list of three entries ordered by ordinal)
- assert `one.previous == nil`
- assert `one.requires == []`
- assert `Enum.map(one.required_by, & &1.ordinal) == [2, 3]`
- assert `two.previous.ordinal == 1`
- assert `Enum.map(two.requires, & &1.ordinal) == [1]`
- assert `three.next == nil`
- assert `Enum.map(three.requires, & &1.ordinal) == [1, 2]`
- assert `three.required_by == []`
- Assertions: 8. Guide entry fields used: `previous`, `next`, `requires`, `required_by` (entries have `.ordinal`).

### test "stats count what is there"
- `w = draft(user, "1. One")`, `{:ok, _} = Folders.move_work(user.id, w.id, folder.id)` (no Step inserted).
- assert `%{documents: 1, read: 0} = Stacks.stats(user.id, folder.id)`
- Assertions: 1.

Behavior not obvious from the code:
- Ordering rule: by leading number only if EVERY title has a unique leading integer; numbers compare numerically ("10." after "9."); any missing or duplicate number falls back to insertion (creation) order. Note that the fallback tests create the numbered work first, so they do not distinguish insertion order from other fallbacks.
- `validate/3` matches quotes whitespace-insensitively and stores the document's own wording ("re-wrapped on the way in, stored as the document has it").
- Excerpt = the whole blank-line-delimited paragraph containing the quote, verbatim; maximum two excerpts, extras silently truncated (dropped stays `[]`).
- `requires` entries must be integers strictly below the document's ordinal; drop messages contain "requires 5", "requires 9", "not a number".
- `validate_deep` treats `revised_by` 0 and empty strings as none (nil); a revision is kept only if `revised_by` is an ordinal in `later` and `revision_quote` is found in that step's summary; otherwise `revised_by` and `revision` become nil.
- `validate_story` removes a repeated step from the later part, orders movements by their steps, drops parts with blank prose (their steps become uncovered), and reports uncovered steps in both `uncovered` and a `dropped` message containing `appear in no part: 3, 4`.

---

## test/marginalia/stack_leak_test.exs  (9 tests; covers Stacks.scrub/2, validate_story/2, validate/3)

Module `Marginalia.StackLeakTest`, `use ExUnit.Case, async: true` (NO database). `alias Marginalia.Stacks`.

Moduledoc (verbatim): "The model leaking its own markup into the answer. From the composed telling of a 111-step stack: one part of eleven wrote 12,668 good characters, then emitted a tool-call preamble and the literal word "placeholder", and stopped. It validated clean, was stored, and went out on the public page — where it read as a code block somebody had failed to format."

Module attribute (comment: "The real thing, fullwidth pipes and all (U+FF5C)."), bytes checked with od:
```
@leak "<｜｜DSML｜｜ calls>\n" <>
        "<｜｜DSML｜｜ invoke name=\"write_part\">\n" <>
        "<｜｜DSML｜｜ parameter name=\"prose\" string=\"true\">placeholder"
```
Each marker is `<`, two U+FF5C characters, `DSML`, two U+FF5C characters, then a space and the tag remainder. Three lines joined by "\n", no trailing newline. Copy the pipes from the test file rather than retyping.

### describe "scrub/2"  (Stacks.scrub(text, label) -> {clean_text, reason_or_nil})

### test "ordinary prose is left exactly alone"
- text = `"The backend declares Blimp's syntax in one out-grammar file."`
- assert `Stacks.scrub(text, "part") == {text, nil}`
- Assertions: 1.

### test "prose that mentions angle brackets or pipes is not a false positive"
- text = ``"A generic `List<Int>` and a shell pipe `a | b` are both ordinary prose."``
- assert `{^text, nil} = Stacks.scrub(text, "part")`
- Assertions: 1.

### test "the good prose is kept and the leak is cut"
- `{clean, reason} = Stacks.scrub("Real prose here.\n\n" <> @leak, "part \"Five\"")` (label is the string `part "Five"`)
- assert `clean == "Real prose here."` (trailing whitespace before the leak trimmed)
- refute `clean =~ "DSML"`
- refute `clean =~ "placeholder"`
- assert `reason =~ "leaked its own tool-call markup"`
- assert `reason =~ "part \"Five\""` (label embedded verbatim)
- Assertions: 5.

### test "twelve thousand good characters are not thrown away over a corrupt tail"
- `long = String.duplicate("real sentence. ", 800)`; `{clean, reason} = Stacks.scrub(long <> @leak, "part")`
- assert `String.length(clean) > 11_000`
- assert `reason` (truthy)
- Assertions: 2.

### test "a leak with nothing before it leaves nothing behind"
- assert `{"", reason} = Stacks.scrub(@leak, "part")`
- assert `reason` (truthy)
- Assertions: 1 (+ the pattern match).

### describe "validate_story/2"

### test "a leaking part is cut and the cut is reported, not swallowed"
- steps = `[%{ordinal: 1}, %{ordinal: 2}]` (plain maps)
- raw: `%{"title" => "A telling", "opening" => "The opening.", "closing" => "The closing.", "movements" => [%{"heading" => "One", "prose" => "Good prose.\n\n" <> @leak, "steps" => [1, 2]}]}`
- `{story, dropped, uncovered} = Stacks.validate_story(raw, steps)`
- assert `uncovered == []`
- assert `[m] = story.movements`
- assert `m["prose"] == "Good prose."`
- refute `m["prose"] =~ "DSML"`
- assert any dropped `=~ "leaked its own tool-call markup"` with message "the page renders `dropped`, so a silent cut is the one thing this must not do"
- Assertions: 5.

### test "a leak in the opening or the closing is caught too"
- steps `[%{ordinal: 1}]`; raw title "A telling", opening `"Fine so far. " <> @leak`, closing `"Also fine. " <> @leak`, movements `[%{"heading" => "One", "prose" => "Prose.", "steps" => [1]}]`.
- refute `story.opening =~ "DSML"` (dot access on the returned attrs)
- refute `story.closing =~ "DSML"`
- assert `Enum.count(dropped, &(&1 =~ "leaked")) == 2`
- Assertions: 3.

### test "a clean telling reports nothing"
- clean opening "The opening.", closing "The closing.", movement prose "Prose."
- refute any dropped `=~ "leaked"`
- Assertions: 1.

### describe "validate/3, the step pass"

### test "a leaking capability or lesson is cut and reported"
- body = `"The document body, which contains the quote."`
- raw: `%{"capability" => "A real capability. " <> @leak, "lesson" => "Do the thing. " <> @leak, "requires" => [], "pitfall" => "", "pitfall_quote" => "", "excerpts" => []}`
- `{attrs, dropped} = Stacks.validate(raw, body, 2)`
- refute `attrs.capability =~ "DSML"`
- refute `attrs.lesson =~ "DSML"`
- assert `attrs.capability == "A real capability."`
- assert `Enum.count(dropped, &(&1 =~ "leaked")) == 2`
- Assertions: 4.

Behavior not obvious from the code:
- Scrub detects the DSML marker and cuts from its start to the end, trimming whitespace before it; plain angle brackets and ASCII pipes are not triggers.
- A cut must be reported in `dropped` because "the page renders `dropped`".
- Scrubbed fields: movement prose, story opening, story closing, step capability, step lesson. Each yields one "leaked ..." message.

---

## test/marginalia/stack_to_draft_test.exs  (6 tests; covers Marginalia.Stacks.to_draft/2)

Module `Marginalia.StackToDraftTest`, `use Marginalia.DataCase, async: true`, `alias Marginalia.{Folders, Repo, Stacks, Works}`, `alias Marginalia.Stacks.Story`.

Setup:
- `user = user_fixture()`
- `{:ok, folder} = Folders.create_folder(user.id, %{"name" => "A stack"})` (string key here)
- `story` is `fn movements -> Repo.insert!(%Story{folder_id: folder.id, title: "Half of building it is fixing the thing underneath", opening: "Nothing here is hand-written at the level you would expect.", movements: movements, closing: "That is the method.", uncovered: [], dropped: []}) end`
- context `%{user, folder, story}`; tests take `ctx` and call `ctx.story.(movements)`.

Helper (comment: "Over @min_words (250), because a shorter section is merged into the one before it — correctly, and it would make this test prove nothing. Real movements run about 1,700 words."): `long(lead) = lead <> " " <> String.duplicate("word ", 320)`.

`movements()` fixture:
```
[
  %{"heading" => "Get it running first", "prose" => long("Emit one module."), "steps" => [1]},
  %{"heading" => "Lowering is where the semantics live",
    "prose" => long("Every construct needs a shape."),
    "turn" => "This is the part that surprised me.",
    "steps" => [2, 3]}
]
```
No Steps or documents are inserted; only the Story row.

### test "each movement becomes a section, so a note lands on the part it is about"
- `ctx.story.(movements())`; `{:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)`; `sections = Works.list_sections(work.id)`
- assert `work.title == "Half of building it is fixing the thing underneath"`
- assert `length(sections) >= 3`
- `titles = Enum.map(sections, & &1.title)`; assert `"1. Get it running first" in titles`; assert `"2. Lowering is where the semantics live" in titles`
- assert `work.body =~ "That is the method."`
- Assertions: 5.
- Comments (verbatim): "The closing gets its own heading, but a short one is merged into the section before it by the segmenter's @min_words rule. That is right — a two-line section is not worth a note of its own. The `##` itself is gone from the body: a work's body is the join of its sections, and the segmenter lifts a heading into the section title. So what is asserted is that the closing text survives."

### test "the opening, the turns and the closing all survive"
- assert `work.body =~ "Nothing here is hand-written"`
- assert `work.body =~ "This is the part that surprised me."`
- assert `work.body =~ "That is the method."`
- Assertions: 3.

### test "it is not filed into the stack's own folder"
- refute `work.folder_id == ctx.folder.id`, message: "a draft in the stack's folder becomes document N+1 of the series it summarises, re-read as a chapter and shifting every ordinal after it"
- assert `Stacks.documents(ctx.user.id, ctx.folder.id) == []`
- Assertions: 2.

### test "the intent says what the draft is for, so the read is not generic"
- assert `work.intent =~ "2 parts"`
- assert `work.intent =~ "could be acted on"`
- Assertions: 2.

### test "a stack with no telling yet says so rather than making an empty draft"
- No Story inserted.
- assert `{:error, :not_composed} = Stacks.to_draft(ctx.user.id, ctx.folder.id)`
- assert `Works.list_works(ctx.user.id) == []`
- Assertions: 2.

### test "a movement with no turn does not leave a stray quote marker"
- `ctx.story.([%{"heading" => "One", "prose" => long("Just prose."), "steps" => [1]}])`
- `{:ok, work} = Stacks.to_draft(...)`
- refute `work.body =~ ">"`
- Assertions: 1. (A turn renders as a Markdown blockquote with ">"; no ">" may appear anywhere in the body when there is no turn.)

Behavior not obvious from the code:
- The draft is segmented into sections (sections under 250 words merge into the previous one, so the short closing merges).
- The draft is not placed in the stack's folder, so `Stacks.documents/2` stays `[]`.
- `work.intent` is generated: contains "N parts" (N = movement count) and "could be acted on".

---

## test/marginalia/github_access_test.exs  (15 tests, 4 tagged :network; covers Marginalia.Import.GitHub explain/1, list/4, search/2, oldest_first/1)

Module `Marginalia.GitHubAccessTest`, `use ExUnit.Case, async: true` (NO database), `alias Marginalia.Import.GitHub`.

Moduledoc (verbatim): "Reading a public repository without a credential, and being told which kind of "no" came back. Both of these were wrong in a way that only shows up against the real API. An empty token was still sent as `Authorization: Bearer `, which GitHub answers 401 — so somebody who left the box blank, as they should for a public repository, was told their token had been rejected. And every 403 was reported as a refusal, when the common one is an allowance: 60 requests an hour unauthenticated, against three requests per pull request."

### describe "what a refusal is called"  (GitHub.explain/1 -> string)

### test "a rate limit says when it comes back, not that access was denied"
- `soon` = utc_now + 600 seconds as a unix integer; `said = GitHub.explain({:rate_limited, to_string(soon)})` (reset header is a STRING of the unix timestamp)
- assert `said =~ "rate limiting"`
- assert `said =~ "UTC"`
- assert `said =~ ~r/in \d+m\d+s/`
- refute `said =~ "may lack access"`
- Assertions: 4.

### test "a reset already past reads as a wait of nothing, not a negative one"
- reset = now - 60s
- assert `GitHub.explain({:rate_limited, to_string(gone)}) =~ "in 0m0s"`
- Assertions: 1.

### test "a rate limit with no header still says something usable"
- assert `GitHub.explain({:rate_limited, nil}) =~ "few minutes"`
- Assertions: 1.

### test "a query GitHub will not run is quoted back in its own words"
- `said = GitHub.explain({:rejected, ~s("@today-30d" is not a recognized date/time format)})` (message text: `"@today-30d" is not a recognized date/time format`, literal double quotes)
- assert `said =~ "would not run that search"`
- assert `said =~ "not a recognized date/time format"`
- refute `said =~ "422"`, message "the number is what somebody was staring at before"
- Assertions: 3.

### test "a refusal with nothing to quote still says what to look at"
- assert `GitHub.explain({:rejected, nil}) =~ "qualifiers and the dates"`
- Assertions: 1.

### test "a real refusal still names the two reasons it happens"
- `said = GitHub.explain(:forbidden)`
- assert `said =~ "may lack access"`
- assert `said =~ "60 requests an hour"`
- Assertions: 2.

### test "both mention the allowance, since that is what a bulk import hits"
- `soon` = now + 60s; assert `GitHub.explain({:rate_limited, to_string(soon)}) =~ "5000"`
- Assertions: 1.

### describe "against the live API"  (`@describetag :network`; real HTTP to api.github.com; unauthenticated)

### test "a public repository is readable with no token at all"
- `GitHub.list("phoenixframework", "phoenix", nil, state: "closed")` -> `{:ok, candidates}`
- assert `length(candidates) > 0`
- assert `%{repo: "phoenixframework/phoenix", number: n, title: t} = hd(candidates)`
- assert `is_integer(n)`; assert `is_binary(t)`
- Assertions: 3 (+ the `{:ok, _}` match).

### test "an empty string is the same as no token, not a bad one"
- assert `{:ok, _} = GitHub.list("phoenixframework", "phoenix", "", state: "closed")`
- Assertions: 1.

### test "a relative date is translated before it goes over the wire"
- comment: "typed on the page, refused by GitHub as "not a recognized date/time format" until this translated it"
- assert `{:ok, found} = GitHub.search("repo:phoenixframework/phoenix state:closed created:>@today-30d", nil)`
- assert `found != []`
- `cutoff = Date.add(Date.utc_today(), -30)`; for each `c` in found: `{:ok, made} = c.created_at |> String.slice(0, 10) |> Date.from_iso8601()`; assert `Date.compare(made, cutoff) in [:gt, :eq]`
- Assertions: 3 (one inside a loop).

### test "a query GitHub refuses comes back with GitHub's reason, not a number"
- assert `{:error, {:rejected, said}} = GitHub.search("repo:phoenixframework/phoenix created:>whenever", nil)`
- assert `said =~ "date"`
- Assertions: 2.

### describe "the order the documents land in"  (GitHub.oldest_first/1, pure)
Helper `c(number, merged, created \\ nil)` = `%{repo: "a/b", number: number, title: "PR #{number}", merged_at: merged, created_at: created || "2025-01-01T00:00:00Z"}`.

### test "oldest first, by when it landed"
- comment: "GitHub answers newest first, and the order these are created in is the order Stacks reads them forwards in"
- given = `[c(9, "2025-08-01T00:00:00Z"), c(7, "2025-04-01T00:00:00Z"), c(8, "2025-06-01T00:00:00Z")]`
- assert `Enum.map(GitHub.oldest_first(given), & &1.number) == [7, 8, 9]`
- Assertions: 1.

### test "merge order, not number order, when they disagree"
- comment: "opened in January, merged in July: early by number, late by merge, and for "how did this version get out of the door" merge is the order that happened"
- january = `c(1, "2025-07-01T00:00:00Z", "2025-01-01T00:00:00Z")`; june = `c(90, "2025-06-01T00:00:00Z", "2025-06-01T00:00:00Z")`
- assert `Enum.map(GitHub.oldest_first([january, june]), & &1.number) == [90, 1]`
- Assertions: 1.

### test "an unmerged one sorts by when it was opened"
- open = `c(5, nil, "2025-05-01T00:00:00Z")`; merged = `c(4, "2025-09-01T00:00:00Z", "2025-01-01T00:00:00Z")`
- assert `Enum.map(GitHub.oldest_first([merged, open]), & &1.number) == [5, 4]` (key = merged_at, else created_at)
- Assertions: 1.

### test "the sort is total, so a re-listing does not shuffle"
- same = `[c(3, "2025-04-01T00:00:00Z"), c(1, "2025-04-01T00:00:00Z"), c(2, "2025-04-01T00:00:00Z")]`
- assert `Enum.map(GitHub.oldest_first(same), & &1.number) == [1, 2, 3]` (tie-break by number)
- assert `GitHub.oldest_first(same) == GitHub.oldest_first(Enum.reverse(same))`
- Assertions: 2.

Behavior not obvious from the code:
- Four tests need the live GitHub API (`@describetag :network`); they depend on phoenixframework/phoenix and on the unauthenticated limit of 60 requests an hour. An empty-string token must send NO Authorization header (the regression in the moduledoc).
- `explain/1` branches: `{:rate_limited, reset_string_or_nil}` (wording "rate limiting", a UTC time, "in NmMs" countdown clamped at "in 0m0s", mentions "5000"; nil reset -> "few minutes"), `{:rejected, reason_or_nil}` ("would not run that search", quotes GitHub's reason, never prints "422"; nil -> mentions "qualifiers and the dates"), `:forbidden` ("may lack access" and "60 requests an hour").
- Relative dates `@today-30d` in a search query are translated to a concrete date before sending.

---

## test/marginalia/github_document_test.exs  (16 tests, 8 of them in one describe; covers Marginalia.Import.GitHub.document/1)

Module `Marginalia.GitHubDocumentTest`, `use ExUnit.Case, async: true` (NO database), `alias Marginalia.Import.GitHub`.

Moduledoc (verbatim): "What one pull request becomes when it is read as a chapter. The writeup is the author's argument about their own work. The commits are what they actually did, and the sentence that turns out to matter — why the obvious version was wrong — is usually in a commit message and nowhere else. A stack read from descriptions alone cannot see it."

Helpers:
- `pr(attrs)` = `Map.merge(%{ordinal: 1, number: 7, title: "7. A guard that took too much", body: "The guard was too wide, so three responses came back with no body.", url: "https://github.com/o/r/pull/7", commits: []}, attrs)` (no `:files` key unless given)
- `file(path, status \\ "modified", added \\ 3, removed \\ 1)` = `%{path: path, was: nil, status: status, added: added, removed: removed}`
- `commit(subject, detail \\ "")` = `%{sha: "abc12345", message: if(detail == "", do: subject, else: "#{subject}\n\n#{detail}")}`
`GitHub.document(pr_map)` returns a markdown string.

### test "the writeup comes first and the commits follow it"
- doc = document(pr(%{commits: [commit("be-blimp: narrow the guard")]}))
- assert `doc =~ "The guard was too wide"`
- assert `doc =~ "## Commits (1)"`
- assert `doc =~ "be-blimp: narrow the guard"`
- `writeup_at` = byte offset of "The guard was too wide"; `commits_at` = offset of "## Commits"; assert `writeup_at < commits_at`, message "the argument has to survive the window Stacks.text_of/1 reads"
- Assertions: 4.

### test "a commit message keeps its body, which is where the reasoning lives"
- why = `"The obvious version drops the last frame, because the reader is closed first."`; commit("be-blimp: close the reader last", why)
- assert `doc =~ why`
- Assertions: 1.

### test "the short sha rides along, so a claim can be chased"
- commits: one commit("be-blimp: narrow the guard")
- assert `doc =~ "(abc12345)"`
- Assertions: 1.

### test "a pull request with no description still carries its commits"
- `body: ""`, one commit.
- assert `doc =~ "has no description"`
- assert `doc =~ "be-blimp: narrow the guard"`
- Assertions: 2.

### test "no commits adds no section at all"
- `commits: []`
- refute `doc =~ "## Commits"`
- assert `doc =~ "The guard was too wide"`
- Assertions: 2.

### test "a failed commit fetch says so in the document rather than looking empty"
- `commits: {:error, {:http, 502}}`
- assert `doc =~ "could not be fetched"`
- assert `doc =~ "502"`
- refute `doc =~ "## Commits (0)"`, message "a chapter whose trail failed must not read as a chapter that had none"
- Assertions: 3.

### test "a very long trail is cut, and says it was cut"
- many = 400 commits: `for i <- 1..400, do: commit("commit #{i}", String.duplicate("detail ", 40))`
- assert `doc =~ "commit trail truncated"`
- assert `doc =~ "## Commits (400)"`, message "the real count survives the cut"
- assert `String.length(doc) < 14_000`, message "the whole document has to fit the window Stacks.text_of/1 reads"
- Assertions: 3.

### test "the writeup is never what gets cut"
- argument = `"This is the load-bearing sentence of the chapter."`; body: argument; 400 commits as above.
- assert `doc =~ argument`
- Assertions: 1.

### describe "the files it touched"

### test "paths and line counts, between the argument and the commits"
- pr with `files: [file("lib/a.ex"), file("lib/b.ex", "added", 96, 0)]`, `changed_files: 2`, `commits: [commit("narrow the guard")]`
- assert `doc =~ "## Files changed (2)"`
- assert ``doc =~ "- `lib/a.ex` +3 −1"`` (U+2212 MINUS SIGN, not ASCII hyphen)
- assert ``doc =~ "- `lib/b.ex` +96 — new"`` (U+2014 em dash; added file with 0 removed omits the minus part)
- `order = fn needle -> :binary.match(doc, needle) |> elem(0) end`
- assert `order.("The guard was too wide") < order.("## Files changed")`, message "the argument still comes first"
- assert `order.("## Files changed") < order.("## Commits")`, message "the paths are an index; the commits are the story"
- Assertions: 5.

### test "no diff hunks, however the response arrived"
- pr with `files: [file("lib/a.ex")], changed_files: 1`
- refute `doc =~ "@@"`; refute `doc =~ "+++"`; refute `doc =~ "patch"`
- Assertions: 3.

### test "a rename reads as one, not as two files"
- renamed = `%{path: "test/cases_test.exs", was: "test/case_test.exs", status: "renamed", added: 2, removed: 2}`; pr with `files: [renamed], changed_files: 1`
- assert ``doc =~ "- `test/case_test.exs` → `test/cases_test.exs` +2 −2"`` (U+2192 arrow, U+2212 minus)
- Assertions: 1.

### test "a file with no line changes says nothing about lines"
- pr with `files: [file(".formatter.exs", "modified", 0, 0)]` (no changed_files key)
- assert ``doc =~ "- `.formatter.exs`\n" or String.ends_with?(doc, "- `.formatter.exs`")``
- refute `doc =~ "+0"`
- Assertions: 2.

### test "a deleted file is not reported as three added lines"
- `files: [file("lib/gone.ex", "removed", 0, 40)]`
- assert ``doc =~ "- `lib/gone.ex` −40 — deleted"`` (U+2212, U+2014)
- Assertions: 1.

### test "the header counts what the pull request touched, not what fitted"
- many = 80 files `file("lib/f#{i}.ex")` for i in 1..80; `changed_files: 326`
- assert `doc =~ "## Files changed (326, the first 60 listed)"`
- assert ``doc =~ "`lib/f60.ex`"``
- refute ``doc =~ "`lib/f61.ex`"``
- Assertions: 3.

### test "a pull request with no file list is a document without the section"
- pr with only `commits: [commit("x")]` (no :files key)
- refute `doc =~ "Files changed"`
- Assertions: 1.

### test "a fetch that failed says so rather than looking like no files"
- `files: {:error, :forbidden}`
- assert `doc =~ "## Files changed"`
- assert `doc =~ "could not be fetched"`
- assert `doc =~ "forbidden"`
- Assertions: 3.

Behavior not obvious from the code:
- Document layout order: writeup (or a "has no description" note) -> `## Files changed (...)` -> `## Commits (N)`.
- A commit renders subject, "(sha)" and the message body.
- A very long commit trail is truncated with a "commit trail truncated" notice; the header keeps the real count; total length stays under 14,000 characters; the writeup is never truncated.
- File line format: `- ` + backticked path + ` +N` (if added > 0) + ` −N` (if removed > 0) + ` — new` (status "added") or ` — deleted` (status "removed"); renames render `` `was` → `path` ``. Only the first 60 files are listed; header `(326, the first 60 listed)` when changed_files exceeds what is listed, `(2)` when equal. Diff text is never included.
- Fetch errors: `commits: {:error, {:http, 502}}` and `files: {:error, :forbidden}` each produce a "could not be fetched" line containing the reason; a commits failure produces no "## Commits (0)" header.

---

## test/marginalia/github_stack_test.exs  (9 tests; covers Marginalia.Import.GitHub.order/2 and explain/1)

Module `Marginalia.GitHubStackTest`, `use ExUnit.Case, async: true` (NO database), `alias Marginalia.Import.GitHub`.

Moduledoc (verbatim): "A stack is each pull request based on the one before it. Anything else is refused by name, because a silently mis-ordered import produces a method whose steps are in the wrong order and nothing downstream can tell."

Helper `pr(number, head, base, title \\ nil)` = `%{"number" => number, "title" => title || "PR #{number}", "body" => "body #{number}", "html_url" => "https://example.invalid/pull/#{number}", "head" => %{"ref" => head}, "base" => %{"ref" => base}}` (raw GitHub API JSON shape, string keys).
`GitHub.order(pulls, default_branch)` -> `{:ok, items}` (each item has `.number` and `.ordinal`, 1-based) or `{:error, reason}`.

### test "the order comes from the chain, not from the listing"
- pulls = `[pr(3, "c", "b"), pr(1, "a", "main"), pr(2, "b", "a")]`
- assert `{:ok, items} = GitHub.order(pulls, "main")`
- assert `Enum.map(items, & &1.number) == [1, 2, 3]`
- assert `Enum.map(items, & &1.ordinal) == [1, 2, 3]`
- Assertions: 2 (+ the match).

### test "the numbers do not have to agree with the order"
- comment: "renumbered, reordered: the chain is still a: -> b: -> c:"
- pulls = `[pr(90, "b", "a"), pr(12, "a", "main"), pr(7, "c", "b")]`
- assert `{:ok, items} = GitHub.order(pulls, "main")`; assert `Enum.map(items, & &1.number) == [12, 90, 7]`
- Assertions: 1 (+ the match).

### test "two pull requests on the default branch are two stacks, and it says so"
- pulls = `[pr(1, "a", "main"), pr(2, "b", "main")]`
- assert `{:error, {:many_roots, roots}} = GitHub.order(pulls, "main")`
- assert `Enum.sort(roots) == [1, 2]` (PR numbers)
- assert `GitHub.explain({:many_roots, roots}) =~ "more than one stack"`
- Assertions: 2 (+ the match).

### test "a pull request off the chain is named, not dropped"
- pulls = `[pr(1, "a", "main"), pr(2, "b", "a"), pr(9, "stray", "somewhere-else")]`
- assert `{:error, {:off_chain, [9]}} = GitHub.order(pulls, "main")`
- assert `GitHub.explain({:off_chain, [9]}) =~ "#9"`
- Assertions: 2.

### test "nothing based on the default branch is no start to the chain"
- assert `{:error, {:no_root, "main"}} = GitHub.order([pr(1, "a", "zzz")], "main")`
- assert `GitHub.explain({:no_root, "main"}) =~ "no start"`
- Assertions: 2.

### test "an empty repository is refused rather than imported as nothing"
- assert `{:error, :no_pull_requests} = GitHub.order([], "main")`
- Assertions: 1.

### test "two pull requests from one branch is not a stack"
- comment: "the shape that gets through everything else: the walk terminates, the count comes out right, and the order it produces is a guess"
- pulls = `[pr(1, "a", "main"), pr(2, "b", "a"), pr(3, "a", "b")]` (PR 3 head "a" duplicates PR 1 head "a")
- assert `{:error, {:duplicate_branches, ["a"]}} = GitHub.order(pulls, "main")`
- assert `GitHub.explain({:duplicate_branches, ["a"]}) =~ "one pull request per branch"`
- Assertions: 2.

### test "a chain that loops terminates rather than hanging"
- comment: "distinct branches, but c is based on b and b on c"
- pulls = `[pr(1, "a", "main"), pr(2, "b", "c"), pr(3, "c", "b")]`
- assert `{:error, _} = GitHub.order(pulls, "main")` (any error)
- Assertions: 1.

### test "every error explains itself in words someone can act on"
- For each e in `[:unauthorized, :forbidden, :not_found, :bad_name, :no_pull_requests, {:http, 500}, {:transport, "x"}, {:no_root, "main"}, {:duplicate_branches, ["a"]}, {:off_chain, [1]}, {:many_roots, [1, 2]}]`:
  - assert `is_binary(GitHub.explain(e))`
  - refute `GitHub.explain(e) == ""`
- Assertions: 2 (each executed 11 times).

Behavior not obvious from the code:
- Duplicate head branches must be detected even when the chain walk would terminate; a loop must yield an error and not hang.
- `many_roots` carries root PR numbers; `off_chain` carries the unreached PR numbers.
- Required explain substrings: many_roots "more than one stack"; off_chain "#9"; no_root "no start"; duplicate_branches "one pull request per branch".

---

## test/marginalia/git_test.exs  (9 tests, one inside a describe; covers Marginalia.Git)

Module `Marginalia.GitTest`, `use Marginalia.DataCase, async: false`, `import Marginalia.AccountsFixtures`, `alias Marginalia.{Git, Works}`. It shells out to the real `git` binary (moduledoc: "A draft's history as a real repository. The tests run `git` for the same reason the module does: a reimplementation that agrees with itself proves nothing, and the point of this is that the writer can clone the result.").

Setup (per test):
- `root = Path.join(System.tmp_dir!(), "mg-git-#{System.unique_integer([:positive])}")`
- `previous = Application.get_env(:marginalia, :draft_repo_root)`; `Application.put_env(:marginalia, :draft_repo_root, root)`
- on_exit: `Application.put_env(:marginalia, :draft_repo_root, previous)` and `File.rm_rf(root)`
- `user = user_fixture()`
- body = `"# A draft\n\nALPHA the first paragraph. " <> String.duplicate("word ", 120) <> "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`
- context `%{work, user, root}`
Helper `git(work, args)` = `System.cmd("git", args, cd: Git.path(work), stderr_to_stdout: true)`.
Seam: application env `:marginalia, :draft_repo_root`; `Git.path(work)` is the per-work repository directory under root.

### test "the first commit creates a real repository"
- assert `{:ok, sha} = Git.commit(work, "First")`
- assert `sha =~ ~r/^[0-9a-f]{4,}$/`
- assert `File.dir?(Path.join(Git.path(work), ".git"))`
- assert `{out, 0} = git(work, ["log", "--oneline"])`
- assert `out =~ "First"`
- Assertions: 4 (+ the first match).

### test "the document is in the tree, with the draft identified"
- `{:ok, _} = Git.commit(work, "First")`; `contents = File.read!(Path.join(Git.path(work), "draft.md"))`
- assert `contents =~ "ALPHA the first paragraph."`
- assert `contents =~ "slug: #{work.slug}"`
- assert `contents =~ "title: Draft"`
- Assertions: 3. (File is `draft.md` with front-matter lines `slug: ...` and `title: Draft`.)

### test "committing an unchanged draft is not a commit"
- `{:ok, _} = Git.commit(work, "First")`
- assert `Git.commit(work, "Again") == {:ok, :unchanged}`
- assert `{out, 0} = git(work, ["log", "--oneline"])`
- assert `length(String.split(out, "\n", trim: true)) == 1`
- Assertions: 2 (+ the match).

### test "an edit becomes a second commit whose patch is the change"
- `{:ok, _} = Git.commit(work, "As it arrived")`
- `section = hd(Works.list_sections(work.id))`; `block = section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&String.contains?(&1, "ALPHA"))`
- `{:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))`
- `work = Works.get_by_slug(work.slug)`
- assert `{:ok, _sha} = Git.commit(work, "rewrite: cuts the gloss")`
- assert `{:ok, entries} = Git.log(work)`
- assert `[%{subject: "rewrite: cuts the gloss"}, %{subject: "As it arrived"}] = entries` (newest first)
- assert `{:ok, patch} = Git.show(work, hd(entries).sha)`
- assert `patch =~ "-" <> "ALPHA" or patch =~ "ALPHA"`
- assert `patch =~ "AMENDED"`
- Assertions: 6.

### test "a multi-line message is reduced to a subject"
- `{:ok, _} = Git.commit(work, "line one\nline two\n\nline three")`
- assert `{:ok, [%{subject: subject}]} = Git.log(work)`
- refute `subject =~ "\n"`
- assert `subject == "line one line two line three"` (whitespace runs collapsed to single spaces)
- Assertions: 3.

### test "a title with quotes in it does not break the commit"
- second work: `Works.create_work(user.id, %{"title" => ~s(A "quoted" title; rm -rf /), "body" => "# H\n\n" <> String.duplicate("word ", 300)})`
- assert `{:ok, _} = Git.commit(work, "subject with \"quotes\" and $(echo hi)")`
- assert `{:ok, [%{subject: s}]} = Git.log(work)`
- assert `s =~ "quotes"`
- Assertions: 3.

### test "a bad sha is refused rather than passed to git"
- `{:ok, _} = Git.commit(work, "First")`
- assert `Git.show(work, "--not-a-sha") == {:error, :bad_sha}`
- assert `Git.show(work, "; rm -rf /") == {:error, :bad_sha}`
- Assertions: 2.

### test "a log for a draft with no repository says so"
- no commit made.
- assert `Git.log(work) == {:error, :no_repo}`
- Assertions: 1.

### describe "when the deploy has not configured a root"
Setup: `previous = Application.get_env(:marginalia, :draft_repo_root)`, `Application.delete_env(:marginalia, :draft_repo_root)`, on_exit puts previous back; returns `:ok`. It runs after the outer setup.

### test "nothing is written and it says why"
- refute `Git.enabled?()`
- assert `Git.commit(work, "First") == {:error, :not_configured}`
- assert `Git.log(work) == {:error, :not_configured}`
- assert `Git.path(work) == nil`
- Assertions: 4.

Behavior not obvious from the code:
- async: false because it mutates application env. `git` must be on PATH; the module itself must supply a commit author identity (tests set none).
- Subject = whole message with whitespace collapsed; `Git.show/2` validates the sha against a hex-only pattern before running git.
- `Git.commit` of an unchanged document returns `{:ok, :unchanged}` and makes no commit; a first commit returns `{:ok, sha}` with lowercase hex of at least 4 characters.
- Error atoms: `:no_repo`, `:not_configured`, `:bad_sha`.

---

## test/marginalia/decision_graph_test.exs  (24 tests; covers Marginalia.Analysis.DecisionGraph as tool calls, plus Works node/edge/event functions)

Module `Marginalia.Analysis.DecisionGraphTest`, `use Marginalia.DataCase, async: true`, `alias Marginalia.Analysis.DecisionGraph, as: DG`, `alias Marginalia.Works`, `import Marginalia.AccountsFixtures`.

Moduledoc: "The decision-graph skill, as tool calls. Three of its rules are enforced in code rather than asked for in the prompt; these pin them."

Top-level setup:
- `user = user_fixture()`
- body = `"Chapter 1\n\n" <> "She had been standing at the window for an hour before anyone noticed. " <> String.duplicate("word ", 300)`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})`
- context `%{work: work, section: hd(Works.list_sections(work.id))}` (first section; its body contains "She had been standing at the window for an hour before anyone noticed.")

Helpers:
- `call(state, name, args)`: `fun = %{"id" => "x", "function" => %{"name" => name, "arguments" => Jason.encode!(args)}}`; `{msg, state} = :erlang.apply(DG, :execute, [fun, state])` (comment: "the tool loop is private, so drive it the way the model would"; `execute/2` is called through `apply`); returns `{Jason.decode!(msg["content"]), state}`. So `DG.execute(tool_call_map, state)` returns `{message_map_with_"content"_JSON_string, new_state}`; all assertions are on the decoded content map.
- `state(work, section)` = `%{work: work, narrative: "n", sections: [section], nodes: %{}}`. `st.nodes` is a map (keyed by node id).
Tool args use string keys: `"type"`, `"title"`, `"narrative"`, `"quote"`, `"from"`, `"to"`, `"rationale"`, `"id"`, `"status"`.

### describe "the tool surface mirrors the deciduous CLI"

### test "add_node, link and set_status are the three operations"
- `names = Enum.map(DG.tools(), & &1["function"]["name"]) |> Enum.sort()`
- assert `names == ["add_node", "link", "set_status"]`
- Assertions: 1. (`DG.tools/0` returns OpenAI-style function tool maps with string keys.)

### test "add_node offers exactly the decision-graph vocabulary"
- `add = Enum.find(DG.tools(), &(&1["function"]["name"] == "add_node"))`; `types = add["function"]["parameters"]["properties"]["type"]["enum"]`
- assert `Enum.sort(types) == ~w(action decision goal observation option outcome revisit)`
- Assertions: 1.

### describe "grounding is enforced at the tool boundary"

### test "a fabricated quote is refused, and the model is told why"
- add_node `%{"type" => "observation", "title" => "invented", "narrative" => "n", "quote" => "She turned and left without saying anything at all."}`
- assert `result["error"] =~ "not found in the draft"`
- assert `result["hint"] =~ "Copy the span exactly"`
- assert `st.nodes == %{}`, message "the node must not be stored"
- Assertions: 3.

### test "a real quote is accepted and rewritten to the source's wording"
- add_node `%{"type" => "observation", "title" => "real", "narrative" => "n", "quote" => "standing at the window for an hour"}`
- assert `result["id"]` (truthy)
- assert `map_size(st.nodes) == 1`
- `node = Works.get_node(w.id, result["id"])`; assert `String.contains?(sec.body, node.quote)`
- Assertions: 3.

### test "a structural node may omit a quote"
- add_node `%{"type" => "goal", "title" => "the goal", "narrative" => "n"}`
- assert `result["id"]`
- Assertions: 1.

### describe "the flow rule is enforced, not requested"
Setup (uses work/section): builds state, then four add_node calls in order, none with a quote, returning `%{st: st, goal: goal, opt: opt, dec: dec, act: act}`:
- goal: `%{"type" => "goal", "title" => "g", "narrative" => "n"}`
- option: type "option", title "o"
- decision: type "decision", title "d"
- action: type "action", title "a"
(each result has an "id")

### test "goal -> decision is refused with the fix spelled out"
- `call(st, "link", %{"from" => g, "to" => d})`
- assert `result["error"] =~ "a goal cannot lead straight to a decision"`
- assert `result["error"] =~ "options"`
- Assertions: 2.

### test "goal -> option -> decision -> action is allowed"
- For each `{from, to}` in `[{g, o}, {o, d}, {d, a}]`: `call(st, "link", %{"from" => from, "to" => to})`; assert `result["linked"]` with message "expected #{from} -> #{to} to be allowed, got #{inspect(result)}"
- Assertions: 1 (executed 3 times; the original `st` is reused each time).

### test "a step that is not in the flow is refused and the legal ones named"
- `call(st, "link", %{"from" => a, "to" => o})` (action -> option)
- assert `result["error"] =~ "not a step in goal -> option -> decision"`
- assert `is_list(result["allowed"])`
- Assertions: 2.

### test "a node id the model never created cannot be linked"
- `call(st, "link", %{"from" => g, "to" => 999_999})`
- assert `result["error"] =~ "unknown node id"`
- Assertions: 1.

### test "an option can be marked chosen or rejected"  (top level, not in a describe)
- state; add_node option title "o" narrative "n" -> opt id
- `call(st, "set_status", %{"id" => opt, "status" => "rejected"})`
- assert `result["ok"]`
- assert `Works.get_node(w.id, opt).status == "rejected"`
- Assertions: 2.

### describe "the build trace"
Setup: `%{state: state(work, section)}`. Events are persisted: `Works.list_events(work_id)` (fields `ok`, `tool`, `seq`, `node_id`, `result`) and `Works.event_stats(work_id)` (fields `calls`, `refused`, `refusals` (map reason -> count), `by_tool` (map)).

### test "records the calls that succeeded"
- call 1: add_node `%{"type" => "goal", "title" => "A goal", "narrative" => "n"}` -> id
- call 2: add_node `%{"type" => "option", "title" => "An option", "narrative" => "n", "quote" => "standing at the window for an hour"}`
- `events = Works.list_events(work.id)`
- assert `length(events) == 2`
- assert `Enum.all?(events, & &1.ok)`
- assert `Enum.map(events, & &1.tool) == ["add_node", "add_node"]`
- assert `Enum.map(events, & &1.seq) == [0, 1]`
- assert `hd(events).node_id == id`
- Assertions: 5.

### test "records a refused quote as a refusal, not a silent gap"
- add_node `%{"type" => "action", "title" => "Invented", "narrative" => "n", "quote" => "a sentence the writer never wrote at all"}`; result matched against `%{"error" => _}`
- assert `[event] = Works.list_events(work.id)`
- refute `event.ok`
- assert `event.result =~ "character for character"`
- `stats = Works.event_stats(work.id)`; assert `stats.calls == 1`; assert `stats.refused == 1`; assert `stats.refusals["quote not in draft"] == 1`
- Assertions: 5 (+ pattern matches).

### test "records a refused link and names the flow rule"
- add_node goal "G", add_node decision "D" (narrative "n"), then link goal -> decision; result matched against `%{"error" => _}`.
- `stats = Works.event_stats(work.id)`: assert `stats.calls == 3`; assert `stats.refused == 1`; assert `stats.refusals["flow rule"] == 1`; assert `stats.by_tool == %{"add_node" => 2, "link" => 1}`
- Assertions: 4.

### test "a rebuild clears the previous run's trace"
- add_node goal "G"; assert `length(Works.list_events(work.id)) == 1`
- `Works.clear_events(work.id)`
- assert `Works.list_events(work.id) == []`
- assert `Works.event_stats(work.id).calls == 0`
- Assertions: 3.

### describe "malformed tool calls"
Setup `%{state: state(work, section)}`.

### test "a title written under the type key is recovered"
- comment: "a real run produced this three times: the title written under the node type's own key instead of under "title""
- add_node `%{"type" => "action", "action" => "Name the method", "narrative" => "n"}`
- assert `result["added"] == "Name the method"`
- assert `result["type"] == "action"`
- Assertions: 2. (Success results carry "added" = title, "type", "id".)

### test "a genuinely titleless node is still refused, and the error says what was sent"
- add_node `%{"type" => "action", "narrative" => "n"}`
- assert `result["error"] =~ "title"`
- assert `"type" in result["you_sent"]`
- Assertions: 2.

### test "an empty call does not recover a title from nowhere"
- add_node `%{}`
- assert `result["error"] =~ "can't be blank"`
- Assertions: 1.

### describe "refusals are actionable"
Setup `%{state: state(work, section)}`.

### test "a refused link names the legal one-hop route"
- comment: "the commonest illegal link in a real run"
- add_node outcome "O", add_node action "A" (narrative "n"), then link from outcome to action.
- assert `result["error"] =~ "outcome -> action"`
- assert `result["route"] =~ "observation"`
- Assertions: 2.

### test "re-sending a refused call verbatim is called out, not re-run"
- bad = `%{"type" => "action", "title" => "X", "narrative" => "n", "quote" => "not in the draft at all"}`
- first call: assert `first["error"] =~ "character for character"`
- second identical call using the returned state: assert `second["repeat"] == true`; assert `second["error"] =~ "already sent this exact call"`
- Assertions: 3.

### test "a different call after a refusal still runs"
- add_node action "X" quote `"nope nope nope"` (refused); then add_node action "Y" quote `"standing at the window for an hour"` with the returned state.
- assert `ok["added"] == "Y"`
- assert `Works.event_stats(work.id).refused == 1`
- Assertions: 2.

### describe "rebuilding replaces rather than stacks"

### test "the previous decision graph is cleared, the read is not"
- Comment: "a read, and a decision graph built on top of it".
- `{:ok, beat} = Works.insert_node(%{work_id: work.id, section_id: section.id, node_type: "beat", title: "a beat"})`
- `{:ok, spine} = Works.insert_node(%{work_id: work.id, node_type: "spine", title: "the trunk"})`
- add_node goal "G", add_node option "O"; link goal -> option.
- `Works.link(work.id, beat.id, spine.id, "realises", 0, "why")` (arity 6)
- assert `{:ok, 2} = Works.reset_decision_graph(work.id)` (count of deleted nodes: the goal and the option)
- `kept = Works.list_nodes(work.id) |> Enum.map(& &1.node_type) |> Enum.sort()`; assert `kept == ["beat", "spine"]`
- comment "the edge between two surviving nodes survives with them"; assert `[%{edge_type: "realises"}] = Works.list_edges(work.id)` (the goal->option edge is gone)
- assert `Works.list_events(work.id) == []`
- Assertions: 2 plus 2 pattern matches (3 `assert` lines with =, ==: total 4 assert calls).

### test "clearing an empty graph is not an error"
- assert `{:ok, 0} = Works.reset_decision_graph(work.id)`
- Assertions: 1.

### describe "narratives are not sealed islands"

### test "a node from an earlier narrative can be linked to"
- narrative one: st = state; add_node `%{"type" => "outcome", "title" => "Where one ended", "narrative" => "one"}` -> id `first`; `carried = st.nodes`
- `st2 = %{state(work, section) | narrative: "two", nodes: carried}`
- add_node `%{"type" => "observation", "title" => "What two noticed", "narrative" => "two"}` -> id `second`
- link `%{"from" => first, "to" => second, "rationale" => "one caused two"}`
- assert `result["linked"] == "#{first} -> #{second}"`
- Assertions: 1.

### test "an id from no narrative at all is still refused, and says what is known"
- add_node goal "G" (narrative "n") -> id a; link `%{"from" => a, "to" => 999_999}`
- assert `result["error"] =~ "unknown node id"`
- assert `a in result["known"]`
- assert `Works.list_edges(work.id) == []`
- Assertions: 3.

Behavior not obvious from the code:
- Three rules enforced in code: grounding (quotes must be verbatim in the draft; stored quote rewritten to the section's wording), the flow rule (goal -> option -> decision -> action -> outcome; a goal cannot go straight to a decision; outcome -> action is illegal and the route suggests going via an observation), and refusal accounting.
- Refusal categories in `event_stats.refusals` keyed by exact strings: "quote not in draft", "flow rule". Text anchors: quote refusals contain "not found in the draft" (error), "Copy the span exactly" (hint), "character for character" (also in the stored event result).
- Error JSON fields: `error`, `hint`, `allowed` (list), `route`, `you_sent` (list of keys), `known` (list of ids), `repeat: true` on an exact resend of a refused call (memory is held in the returned state).
- Structural nodes (goal) may omit a quote; quote-bearing nodes are validated.
- Node ids are integers; 999_999 is used as a never-created id.
- Observation after outcome (outcome -> observation) is a legal link.
- `Works.insert_node/1` with node_type "beat"/"spine" is the read layer that survives `reset_decision_graph`.

---

## test/marginalia/walkthrough_test.exs  (13 tests; covers Marginalia.Walkthrough and Marginalia.Rewrite.clean/2)

Module `Marginalia.WalkthroughTest`, `use ExUnit.Case, async: true` (NO database), `alias Marginalia.Walkthrough`.

Moduledoc (verbatim): "The walkthrough drives the real controls, so its fixtures have to be the real shapes. The bug this file exists for: the canned rewrite was written with string keys, `rewrite_panel` reads `c.text`, and the render raised — which in a LiveView does not show an error, it drops the socket. The tour got to step eight and the page quietly stopped responding."

For reference (read from lib, not asserted verbatim): the `:read` steps have ids in order margin, filters, filters_back, map, thread, ask, select, rewrite, edit, done (10 steps). Acts: push `%{kind: "push", event: "set_only", params: %{"only" => ...}}`; client `%{kind: "client", name: ...}`.

### describe "steps"

### test "the read view has one and every step is well formed"
- `steps = Walkthrough.steps(:read)`; assert `length(steps) >= 8`
- For each step s (atom-key maps): assert `is_binary(s.id) and s.id != ""`; assert `is_binary(s.title) and s.title != ""`; assert `is_binary(s.body) and s.body != ""`; assert `is_nil(s[:target]) or is_binary(s[:target])`; assert `s.place in ~w(left right bottom top centre)`
- Assertions: 6 (5 inside a loop).

### test "every id is distinct — the hook indexes by position and reports by id"
- `ids = Walkthrough.steps(:read) |> Enum.map(& &1.id)`; assert `ids == Enum.uniq(ids)`
- Assertions: 1.

### test "every action is one the client knows how to perform"
- known_client = `~w(open_map open_thread ask_thread select rewrite edit reset)`
- For each step with `act = s[:act]` (steps without :act skipped): `%{kind: "push", event: e}` -> assert `is_binary(e)`; `%{kind: "client", name: n}` -> assert `n in known_client`, message "unknown client action #{n}". Any other shape raises CaseClauseError.
- Assertions: 2 (in a loop).

### test "it ends by putting the page back"
- `last = Walkthrough.steps(:read) |> List.last()`; assert `last.act == %{kind: "client", name: "reset"}` (exact map)
- Assertions: 1.

### test "the steps survive the trip to the browser as JSON"
- `json = Walkthrough.steps(:read) |> Jason.encode!() |> Jason.decode!()`
- assert `length(json) == length(Walkthrough.steps(:read))`
- assert `Enum.all?(json, &is_map/1)`
- Assertions: 2.

### test "a reader who does not own the draft is not shown controls they lack"
- comment: "found on production: as a guest, the ask and edit steps spotlit a composer and an editor that are never rendered for a non-owner, so two of the ten steps narrated something that had not happened"
- `theirs = Walkthrough.steps(:read, mine?: false) |> Enum.map(& &1.id)`
- refute `"ask" in theirs`; refute `"edit" in theirs`; refute `"rewrite" in theirs`
- comment "what is left still works for them, and still puts the page back": assert `"thread" in theirs`; assert `"filters" in theirs`; assert `List.last(theirs) == "done"`
- Assertions: 6.

### test "the owner gets all of them"
- `mine = Walkthrough.steps(:read, mine?: true) |> Enum.map(& &1.id)`
- assert `"ask" in mine and "edit" in mine and "rewrite" in mine`
- assert `length(mine) > length(Walkthrough.steps(:read, mine?: false))`
- Assertions: 2.

### test "views without one get an empty list rather than an error"
- assert `Walkthrough.steps(:graph) == []`
- assert `Walkthrough.steps(:spine) == []`
- refute `Walkthrough.for_view?(:graph)`
- assert `Walkthrough.for_view?(:read)`
- Assertions: 4.

### describe "fixtures"

### test "the canned rewrite has the shape Rewrite.propose returns"
- `r = Walkthrough.rewrite()` (arity 0)
- assert `is_binary(r.original) and r.original != ""`
- assert `is_binary(r.reading)`
- assert `Map.has_key?(r, :section)`
- assert `length(r.candidates) == 3`
- Assertions: 4.

### test "candidates carry the atom keys the panel reads, not strings"
- comment: "`rewrite_panel` renders c.move / c.cost / c.text. A string-keyed map raises there, and a raise in render takes the whole LiveView down."
- For each c in `Walkthrough.rewrite().candidates`: assert `is_binary(c.text) and c.text != ""`; assert `is_binary(c.move) and c.move != ""`; assert `is_binary(c.cost) and c.cost != ""`
- Assertions: 3 (in a loop).

### test "the fixture keys match what Rewrite actually produces"
- `produced = Marginalia.Rewrite.clean([%{"text" => "a rewritten line", "move" => "Cuts it", "cost" => "Loses the aside"}], "the line as it stands")` (clean/2: raw string-keyed candidates, original text)
- assert `[%{}] = produced` (one candidate)
- assert `Map.keys(hd(produced)) |> Enum.sort() == Walkthrough.rewrite().candidates |> hd() |> Map.keys() |> Enum.sort()` (identical key sets, atom keys; at least `:cost, :move, :text`)
- Assertions: 2.

### test "no candidate is the original, which the real cleaner also rejects"
- `r = Walkthrough.rewrite()`; refute `Enum.any?(r.candidates, &(&1.text == r.original))`
- Assertions: 1.

### test "the canned answer says it is canned"
- `{question, answer} = Walkthrough.exchange()` (arity 0)
- assert `is_binary(question) and question != ""`
- comment: "a fixture presented as a reading of the writer's own paragraph is the one thing this product must never do"
- assert `answer =~ "never calls the model"`
- Assertions: 2.

Behavior not obvious from the code:
- Step maps use atom keys (`id`, `title`, `body`, `place`, `target`, `act`); `target` may be absent, nil or a string selector; `place` is one of left, right, bottom, top, centre.
- `steps(view, opts)`: `:read` has at least 8 steps (10 for the owner; default `mine?` is true); `mine?: false` removes ask, edit, rewrite; `:graph` and `:spine` return `[]`.
- The canned rewrite must use atom-keyed candidates because a string-keyed map raised in `rewrite_panel` and killed the LiveView socket (the regression the file exists for).
- No LLM is called; `exchange/0` answer text discloses "never calls the model".

---

## Totals

Assertion counts are lines containing assert/refute (grep-based; a loop body counts once, so executed counts are higher; per-test counts above may differ by a few where a line holds `and`/`or` conditions or `Enum.any?` wrappers).

| file | tests | assert/refute lines |
|---|---|---|
| stacks_test.exs | 26 | 60 |
| stack_leak_test.exs | 9 | 24 |
| stack_to_draft_test.exs | 6 | 15 |
| github_access_test.exs | 15 | 29 |
| github_document_test.exs | 16 | 36 |
| github_stack_test.exs | 9 | 18 |
| git_test.exs | 9 | 30 |
| decision_graph_test.exs | 24 | 56 |
| walkthrough_test.exs | 13 | 36 |

TOTALS: tests=127 assertions=304

# PART 4. Reading, rewrite, revisions, runs, prompts, provider gate, quota, cache, accounts

# C2 -- acceptance spec for Marginalia tests (reading, rewrite, revisions, runs, recovery, prompts, provider gate, quota, cache, accounts)

Conventions: `=~` is Elixir match: `string =~ "str"` means contains; `string =~ ~r/../` means regex match. Test counts include both `test "..."` and the `test("...", ...)` call form (grep -c '^\s*test "' undercounts reading_test.exs by 2 because two tests are written `test("beats alone", ...)`).

---

## test/marginalia/reading_test.exs  (18 tests; covers Marginalia.Reading: page/2, split/1, render_block/3, focus/2)

Module `Marginalia.ReadingTest`, `use Marginalia.DataCase, async: true`, `alias Marginalia.{Reading, Works}`, `import Marginalia.AccountsFixtures`.
Moduledoc: "The page view. Notes sit beside the paragraph that caused them, which is only possible because every note carries a span verified against the source."

Module attribute `@body` (heredoc, trailing newline after last line):
```
# A draft

She had been standing at the window for an hour before anyone noticed.

The kettle went cold on the counter, and nobody moved to fill it again.

By evening the argument had found its real subject, which was not the kettle.
```

Top-level `setup` (applies to every test including those in describe blocks; describe-level setups run after it):
- `user = user_fixture()`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => @body})`
- returns `%{work: work, section: hd(Works.list_sections(work.id))}` (the first section).

### test "a note lands on the paragraph its quote came from"  (ctx: work, section s)
Data: `Works.insert_node(%{work_id: work.id, section_id: s.id, node_type: "beat", title: "The kettle goes cold", quote: "The kettle went cold on the counter"})` must return `{:ok, _}`.
`Reading.page(work)` (arity 1) must match `[page]` (exactly one page; one per section).
Assertions (6):
1. `page.unplaced == []`
2. `with_notes = Enum.filter(page.blocks, &(&1.notes != []))`; `assert [block] = with_notes` (exactly one block has notes)
3. `assert [%{title: "The kettle goes cold"}] = block.notes` (exactly one note)
4. `block.text =~ "kettle went cold"`
5. `block.mark == "The kettle went cold on the counter"` (mark is the exact quote)
6. `block.ref =~ ~r/^s\d+p\d+$/` -- comment: "every paragraph carries a stable id the rail can point a note at"
Shape implied: page is a map with `:blocks` (each a map with `:notes`, `:text`, `:mark`, `:ref`) and `:unplaced`; notes are maps with `:title` and `:kind`.

### test "a note whose quote is nowhere is kept, not silently dropped"  (ctx: work, section s)
Data: `Works.insert_node(%{work_id: work.id, section_id: s.id, node_type: "beat", title: "Invented", quote: "a sentence that is not in this draft at all"})` -> `{:ok, _}`. `[page] = Reading.page(work)`.
Assertions (2):
1. `Enum.all?(page.blocks, &(&1.notes == []))`
2. `assert [%{title: "Invented"}] = page.unplaced`

### describe "the draft's own markdown"
Module attribute `@code` (heredoc):
~~~
Create a new file:

```elixir
defmodule Producer do
  use GenStage

  def handle_demand(demand, state) do
    {:noreply, [], state}
  end
end
```

The consumer is in control. It's **impossible** to overwhelm it.

1. First principle
2. Second principle
~~~
(The fence contains a blank line between `use GenStage` and `def handle_demand`.) Private helper in the describe: `html_of({:safe, h})` = `IO.iodata_to_binary(h)`. These tests do not use the top-level setup data.

#### test "a fenced code block survives the blank lines inside it"
Comment above test: "a fence contains blank lines, and splitting on those tore it in half: the draft came out as reflowed serif with stray backticks in it".
`blocks = Reading.split(@code)` (split/1 returns a list of block strings); `fence = Enum.find(blocks, &String.starts_with?(&1, "```"))`.
Assertions (3):
1. `assert fence, "the fence should be one block"`
2. `fence =~ "handle_demand"`
3. `fence =~ "end\n```"`

#### test "a fence renders as code, not as prose"
`fence = Reading.split(@code) |> Enum.find(&String.starts_with?(&1, "```"))`; `html = fence |> Reading.render_block(nil, "x") |> html_of()` (render_block/3: text, mark-or-nil, anchor id; returns `{:safe, iodata}`).
Assertions (2): `html =~ "<pre><code"`; `refute html =~ "`"` message "no backticks should reach the page" (no backtick character anywhere in the output).

#### test "a list renders as a list"
`list = Reading.split(@code) |> Enum.find(&String.starts_with?(&1, "1."))` (so split yields "1. First principle\n2. Second principle" as its own block); assert `Reading.render_block(list, nil, "y") |> html_of() =~ "<ol>"`. (1 assertion)

#### test "a highlight survives rendering, even across inline markup"
`para = Reading.split(@code) |> Enum.find(&String.contains?(&1, "impossible"))` (the paragraph "The consumer is in control. It's **impossible** to overwhelm it.").
`html = para |> Reading.render_block("It's **impossible** to overwhelm it", "z") |> html_of()`.
Assertions (3):
1. `html =~ ~s(<mark id="anchor-z">)`
2. `html =~ "<strong>impossible</strong>"` (comment: "the bold inside the span is still bold, and the mark wraps it")
3. `html =~ "</mark>"`

#### test "a block with no highlight gets no mark"
Same `para`. `refute Reading.render_block(para, nil, "z") |> html_of() =~ "<mark"`. (1)

#### test "the sentinels never reach the page"
Same `para`; `html = Reading.render_block(para, "The consumer is in control", "z") |> html_of()`.
Assertions (2): `refute html =~ "\u{E000}"`; `refute html =~ "\u{E001}"` (private-use codepoints U+E000 and U+E001 are internal mark sentinels and must never appear in output).

### describe "trimming"
setup (receives %{work, section: s}):
```
[a, b] = Works.insert_nodes(work.id, s.id, [
  %{node_type: "beat", title: "The window", quote: "standing at the window for an hour"},
  %{node_type: "beat", title: "The kettle", quote: "The kettle went cold on the counter"}
])
Works.link(work.id, a.id, b.id, "tension", 0, "the two do not sit together")
%{a: a, b: b}
```
(`Works.insert_nodes/3` returns the inserted nodes in order; `Works.link/6` args: work_id, from_id, to_id, kind, ordinal 0, body.)
Helper: `kinds(work, only)` = `work |> Reading.page(only: only) |> Enum.flat_map(& &1.blocks) |> Enum.flat_map(& &1.notes) |> Enum.map(& &1.kind) |> Enum.sort()`. So `Reading.page/2` takes keyword `only:` (nil | "beats" | "tensions"), and each note has `:kind` ("beat" for beats; the connection's kind, here "tension", for connections). Connections appear as notes in a block, and are counted once.

#### test "everything shows beats and connections"
assert `kinds(work, nil) == ["beat", "beat", "tension"]` (1)

#### test("beats alone")   (written `test("beats alone", %{work: work}, do: assert(...))`)
assert `kinds(work, "beats") == ["beat", "beat"]` (1)

#### test("tensions alone")
assert `kinds(work, "tensions") == ["tension"]` (1)

### describe "focus/2"
Uses top-level setup. `Reading.focus(work, key)` with a string key.

#### test "a beat carries its own section in full"
Data: `{:ok, n} = Works.insert_node(%{work_id: work.id, section_id: s.id, node_type: "beat", title: "The kettle", quote: "The kettle went cold on the counter"})`.
`focus = Reading.focus(work, "beat:#{n.id}")`.
Assertions (4): `focus.kind == "beat"`; `focus.title == "The kettle"`; `assert [%{id: id}] = focus.sections` (exactly one section); `id == s.id`.

#### test "a connection carries both ends' sections"
Data:
```
two = "# One\n\n" <> String.duplicate("early ", 300) <> "\n\n# Two\n\n" <> String.duplicate("later ", 300)
{:ok, work2} = Works.create_work(work.user_id, %{"title" => "Two", "body" => two})
[s1, s2] = Works.list_sections(work2.id) |> Enum.take(2)
{:ok, a} = Works.insert_node(%{work_id: work2.id, section_id: s1.id, node_type: "beat", title: "A"})
{:ok, b} = Works.insert_node(%{work_id: work2.id, section_id: s2.id, node_type: "beat", title: "B"})
Works.link(work2.id, a.id, b.id, "pays_off", 0, "A promises what B delivers")
```
(nodes have no quote.) `focus = Reading.focus(work2, "conn:#{a.id}:#{b.id}:pays_off")`.
Assertions (5): `focus.kind == "pays_off"`; `focus.body == "A promises what B delivers"`; `length(focus.sections) == 2`; `Enum.map(focus.sections, & &1.ordinal) == [1, 2]`; `s.id != s1.id` (sanity: second work's sections are distinct from the first work's).
Note: `create_work` splits on the "# One"/"# Two" headings into two sections with ordinals 1 and 2.

#### test "a nonsense key is nil rather than a crash"
Assertions (2): `Reading.focus(work, "beat:999999") == nil`; `Reading.focus(work, "garbage") == nil`.

### describe "a highlight that lands on markdown syntax"
These do not use the setup data (the top-level setup still runs).

#### test "emphasis around the quote still renders, and the mark sits inside it"
Comment: "a beat is anchored to a literal substring of the draft, and the draft is markdown -- so a quote of a bolded sentence carries its ** along. Wrapping that in the mark sentinel used to break the delimiter pair and print four asterisks at the reader."
```
text  = "Prudence. **We must slow the pace. Progress will still seem fast.** Two things."
quote = "**We must slow the pace. Progress will still seem fast.**"
{:safe, html} = Marginalia.Reading.render_block(text, quote, "r1")
```
`html` (the payload of `{:safe, _}`) is used directly with `=~` and no IO.iodata_to_binary, so the payload must be a binary (or something `=~` accepts), unlike reading_render_test.
Assertions (3): `refute html =~ "**"`; `html =~ "<strong>"`; `html =~ ~s(<mark id="anchor-r1">We must slow the pace.)` (the mark opens just after the leading `**` is consumed, inside the `<strong>`).

#### test "italics and code fences at the edges are trimmed out of the mark too"
Loop `for {open, close, tag} <- [{"*", "*", "em"}, {"`", "`", "code"}]`:
`text = "Before #{open}the marked words#{close} after."`; `{:safe, html} = Marginalia.Reading.render_block(text, "#{open}the marked words#{close}", "r2")`.
Assertions per iteration (3 source assertions, executed twice):
- `html =~ "<#{tag}>"` (i.e. `<em>` then `<code>`)
- `html =~ "<mark"`
- `refute html =~ "#{open}the marked"` (no "*the marked" resp. no backtick-"the marked" in output)
Inputs: text "Before *the marked words* after." quote "*the marked words*"; text "Before `the marked words` after." quote "`the marked words`".

#### test "a quote that is only delimiters marks nothing rather than crashing"
`text = "Some prose with ** in it somewhere."`; `{:safe, html} = render_block(text, "**", "r3")`; assert `is_binary(html)` (1).

#### test "an ordinary quote is untouched"
`text = "She had been standing at the window for an hour."`; `render_block(text, "standing at the window", "r4")`; assert `html =~ ~s(<mark id="anchor-r4">standing at the window</mark>)` (1).

Behavior not obvious from the code:
- Reading.split/1 must not split inside a fenced code block even across blank lines (regression: "splitting on those tore it in half: the draft came out as reflowed serif with stray backticks in it").
- The mark is implemented with private-use sentinels U+E000/U+E001 internally; they must never appear in output. A quote carrying markdown delimiters (`**`, `*`, backtick) at its edges has those delimiters trimmed out of the mark so the delimiter pair stays intact (regression: "used to break the delimiter pair and print four asterisks at the reader").
- A delimiter-only quote marks nothing; must still return a binary.
- Notes whose quote is not found in any paragraph are returned in `page.unplaced`, never dropped. Nodes with no quote at all are used only in the focus tests.
- `block.ref` format is `s<ordinal>p<index>`; index is 0-based per section (confirmed by rewrite_test covered_refs).
- Assertions recorded in this file: 42.

---

## test/marginalia/reading_render_test.exs  (6 tests; covers Marginalia.Reading.render_block/3,4 and split/1)

`use ExUnit.Case, async: true` (no DB), `alias Marginalia.Reading`. Moduledoc: "A draft is stored one sentence per line. On the page, a paragraph is a paragraph: its sentences run on from one another, and only a blank line in the draft makes a break."
In every test the result is `{:safe, html}` then `html = IO.iodata_to_binary(html)` (except where noted).

### test "sentences on separate lines render as one paragraph"
`Reading.render_block("One sentence.\nAnother sentence.\nA third.", nil, 1)`.
Assertions (2): `refute html =~ "<br"`; `html =~ "<p>One sentence.\nAnother sentence.\nA third.</p>"` (newlines preserved verbatim inside one `<p>`).

### test "a blank line in the draft is a paragraph break, and the highlight survives"
- `Reading.split("One.\nTwo.\n\nThree.\nFour.")` == `["One.\nTwo.", "Three.\nFour."]` (assert ==).
- `Reading.render_block("Three.\nFour.", "Four.", 2)` -> html; assert `html =~ ~s(<mark id="anchor-2">Four.</mark>)` (anchor id arg is the integer 2, rendered "anchor-2"); `refute html =~ "<br"`.
Assertions (3).

### test "emphasis that opens on one sentence line and closes on the next still pairs"
`Reading.render_block("This is *very\nimportant* indeed.", nil, 3)`; assert `IO.iodata_to_binary(html) =~ "<em>very\nimportant</em>"`. (1)

### test "a fenced block keeps every newline, soft breaks or not"
`Reading.render_block("```\na. B.\n\nc. D.\n```", nil, 4)`; assert output `=~ "<code>a. B.\n\nc. D.\n</code>"` (no language class on `<code>`; code text keeps its trailing newline before `</code>`). (1)

### test "a rewrite preview whose original spans a sentence break still diffs in place"
```
text = "One sentence.\nAnother sentence.\nA third."
preview = %{original: "sentence.\nAnother sentence.", text: "sentence.\nA second sentence."}
Reading.render_block(text, nil, 5, preview)   # arity 4: fourth arg is the preview map
```
Assertions (3): `html =~ "<del class=\"mg-cut\">"`; `html =~ "<ins class=\"mg-swap\">"`; `refute html =~ "<br"`.

### test "a highlight that starts on one line and ends on the next is one mark"
`Reading.render_block("One.\nTwo.\nThree.", "Two.\nThree.", 6)`; assert `html =~ ~s(<mark id="anchor-6">Two.\nThree.</mark>)`. (1)

Behavior not obvious from the code:
- Soft line breaks (single `\n`) are never turned into `<br>`; they pass through as literal newlines inside `<p>`, `<em>`, `<mark>`.
- render_block/4 with a preview map `%{original:, text:}` renders an in-place word diff using `<del class="mg-cut">` and `<ins class="mg-swap">`, even when the original spans a newline.
- Assertions recorded: 11.

---

## test/marginalia/rewrite_test.exs  (30 tests; covers Marginalia.Rewrite: propose/2, answer_budget/1, tool/0, diff/2, steer_block/1, max_steer_chars/0, span_label/1, span_extent/1, place/3, covered_refs/2; plus Marginalia.LLM.reasoning_headroom/1)

`use Marginalia.DataCase, async: true`; aliases `Marginalia.{Rewrite, Works}`; `import Marginalia.AccountsFixtures`. Moduledoc: "The one place in the product that writes prose for the manuscript. The constraints on it are what stop that swallowing the rest."
Top-level setup:
```
user = user_fixture()
body = "# A draft\n\nThe kettle went cold on the counter, and nobody moved to fill it again.\n\n" <> String.duplicate("word ", 300)
{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
%{work: work}
```
No LLM is called in this file: every `propose/2` call returns before any provider call. No put_env, no stubs.

### describe "the span has to be real"

#### test "a selection that is not in the draft gets nothing"
assert `{:error, :not_in_draft} = Rewrite.propose(work, "a sentence nobody wrote")`. (1)

#### test "a redraft is refused, and says how long it was"
`long = String.duplicate("word ", 3_000)` (3000 words).
Assertions (3): `assert {:error, {:span_too_long, words, max}} = Rewrite.propose(work, long)`; `words > max`; `max == 2_500`.

#### test "a long passage is not a redraft any more"
Comment: "400 words used to be refused outright. At a median paragraph of 248 words that is barely a paragraph and a half."
`sel = String.duplicate("a sentence that is not in this draft. ", 60)` (60 repetitions of an 8-word sentence = 480 words). assert `{:error, :not_in_draft} = Rewrite.propose(work, sel)` with message "it must get past the length check and go looking for the span". (1)

#### test "the largest request stays inside what the provider accepts"  (ctx unused)
Comment: "deepseek-flash was probed at 27_000, 41_500 and 65_536: all 200. LLM adds reasoning headroom on top of the answer budget, so this is what actually goes out for the biggest span the check allows."
```
biggest = String.duplicate("word ", 2_500)
total = Rewrite.answer_budget(biggest) + Marginalia.LLM.reasoning_headroom(:deepseek)
assert total <= 65_536, "a span at the ceiling must not ask the provider for more than it takes"
```
(1) `Rewrite.answer_budget/1` (String -> integer) plus `LLM.reasoning_headroom/1` (atom -> integer) must sum to <= 65536 for a 2500-word span.

#### test "the answer budget grows with the span, or the reply comes back truncated"
`short = String.duplicate("word ", 40)`; `long = String.duplicate("word ", 2_500)`.
Assertions (2): `Rewrite.answer_budget(short) == 3_000` ("a floor for short spans"); `Rewrite.answer_budget(long) >= 2_500 * 3 * 1.4` (>= 10500.0; comment: "three candidates at ~1.4 tokens a word, and the two labels each").

#### test "several paragraphs get past the length check"
Comment: "80 words: not a length complaint, it goes on to look for the span" (the code is `String.duplicate("a sentence that is not in this draft. ", 10)`: 10 repetitions of an 8-word sentence). assert `{:error, :not_in_draft} = Rewrite.propose(work, sel)`. (1)
(Describe total: 9)

### describe "the tool"

#### test "asks for the move and the cost, not just the words"
`props = Rewrite.tool()["function"]["parameters"]["properties"]` (tool/0 returns an OpenAI-style function-tool map with string keys); `item = props["rewrites"]["items"]`.
Assertions (2): `Enum.sort(item["required"]) == ["cost", "move", "text"]`; `assert props["reading"], "the writer should see what it thought it was changing"` (a "reading" property must exist).

### describe "the word diff"   (Rewrite.diff/2 -> list of `{:same | :del | :ins, string}`)

#### test "both sides reconstruct exactly"
`a = "The kettle went cold on the counter, and nobody moved to fill it again."`; `b = "The kettle went cold, and nobody moved."`; `d = Rewrite.diff(a, b)`.
Assertions (2): concatenating (no separator) the texts of all non-`:ins` pieces `== a`; concatenating all non-`:del` pieces `== b` (so whitespace must live inside the pieces).

#### test "identical spans are all one piece"
assert `[{:same, "a b c"}] = Rewrite.diff("a b c", "a b c")`. (1)

#### test "it finds the shared middle rather than replacing everything"
`d = Rewrite.diff("the cat sat on the mat", "the dog sat on the mat")`.
Assertions (3): some `{:same, t}` with t containing "sat on the mat"; some `{:del, t}` with t containing "cat"; some `{:ins, t}` with t containing "dog".

#### test "an empty original is all insertion"
assert `[{:ins, "new text"}] = Rewrite.diff("", "new text")`. (1)

### describe "the writer's optional steer"   (Rewrite.steer_block/1)

#### test "no steer adds nothing to the prompt"
Assertions (3): `steer_block(nil) == ""`; `steer_block("") == ""`; `steer_block("   ") == ""` with message "whitespace is not an instruction".

#### test "what they typed goes in, in their words"
`block = Rewrite.steer_block("lead with the finding, drop the hedging")`. Assertions (2): `block =~ "lead with the finding, drop the hedging"`; `block =~ "WHAT THE WRITER ASKED FOR"`.

#### test "every candidate must obey it, but they still have to differ"
`block = Rewrite.steer_block("make it shorter")`. Assertions (2): `block =~ "Every candidate must do this"`; `block =~ "differ"` with message "three candidates that all obey identically is one suggestion printed three times".

#### test "a brief is cut to a note"
`long = String.duplicate("please do the thing. ", 200)`; `block = Rewrite.steer_block(long)`. Assertions (2): `String.length(block) < Rewrite.max_steer_chars() + 300`; `Rewrite.max_steer_chars() == 400`.

### describe "what the panel says it is replacing"

#### test "a short selection is still one line"
assert `Rewrite.span_label("a handful of words here") == "Rewrites of one line"`. (1)

#### test "four paragraphs are not one line"
`four = String.duplicate("word ", 1_050)`; assert `Rewrite.span_label(four) == "Rewrites of 1050 words"`. (1)

#### test "nothing selected claims nothing"
Assertions (2): `span_label(nil) == "Rewrites"`; `span_label("") == "Rewrites"`.

#### test "a short span needs no extent line -- it is all on screen"
Assertions (2): `Rewrite.span_extent("a short selection") == nil`; `Rewrite.span_extent(nil) == nil`.

#### test "a long span shows its head and its tail, because the rest runs off below"
`span = "The beginning of the selection. " <> String.duplicate("middle ", 200) <> "the very end."`; `extent = Rewrite.span_extent(span)`.
Assertions (4): `extent =~ "The beginning of the selection"`; `extent =~ "the very end."`; `extent =~ "…"` (U+2026 ellipsis); `String.length(extent) < 200` with message "it is a label, not the span itself".

#### test "newlines in a multi-paragraph selection are flattened"
`extent = Rewrite.span_extent("First para.\n\n" <> String.duplicate("word ", 60) <> "\n\nLast para.")`. Assertions (2): `refute extent =~ "\n"`; `extent =~ "First para."`.
(Describe total: 12)

### describe "putting a candidate back"   (Rewrite.place/3: block, span, candidate -> {:ok, string} | :not_here)

#### test "it replaces the span inside the paragraph that holds it"
`place("First sentence. The span to replace. Last sentence.", "The span to replace.", "A better span.")`. Assertions (2): `{:ok, out} = ...` (assert match); `out == "First sentence. A better span. Last sentence."`.

#### test "only the first occurrence, so a repeated phrase is not rewritten everywhere"
`place("same. same. same.", "same.", "CHANGED.")`; assertions (2): `{:ok, out}`; `out == "CHANGED. same. same."`.

#### test "a paragraph that does not hold the span is refused, not overwritten"
`place("BRAVO the second paragraph, which has nothing to do with it.", "ALPHA the first paragraph.", "A rewrite of alpha.") == :not_here`. (1)

#### test "the refusal is the whole point: it used to replace the paragraph"
Comment: "the old behaviour returned the candidate here, so one click destroyed a paragraph the writer had not selected". `block = "A paragraph worth keeping."`; `refute match?({:ok, "Some rewrite of other text."}, Rewrite.place(block, "not in here", "Some rewrite of other text."))`. (1)
(Describe total: 6)

### describe "which paragraphs a span covers"   (Rewrite.covered_refs/2: section, span -> list of ref strings)
describe setup: `%{section: hd(Works.list_sections(work.id))}`. Section body is the work body: block index 0 is "# A draft", 1 is "The kettle went cold ...", 2 is the 300-word "word word ..." paragraph. `section.ordinal` is used to build refs.

#### test "a span inside one paragraph covers only it"
`para = section.body |> Marginalia.Reading.split() |> Enum.at(1)`; `bit = String.slice(para, 10, 40)`. Assertions (2): `assert [ref] = Rewrite.covered_refs(section, bit)`; `ref == "s#{section.ordinal}p1"`.

#### test "a span across three paragraphs covers all three"
`[a, b, c | _] = Marginalia.Reading.split(section.body)`; `span = a <> "\n\n" <> b <> "\n\n" <> c`. Assertions (2): `length(refs) == 3`; `refs == ["s#{ord}p0", "s#{ord}p1", "s#{ord}p2"]`.

#### test "a span starting mid-paragraph still covers that paragraph"
`[a, b | _] = split(section.body)`; `span = String.slice(a, -60, 60) <> "\n\n" <> b`. Assertions (2): `"s#{ord}p0" in refs` with message "the paragraph does not contain the span, but the span covers it"; `"s#{ord}p1" in refs`. (a is the short heading "# A draft", so slice(a, -60, 60) is all of a.)

#### test "a span that is not in the section covers nothing"
assert `Rewrite.covered_refs(section, "a sentence nobody wrote") == []`. (1)

#### test "the refs are the ones the page builds"  (ctx: work, section)
`page_refs = Marginalia.Reading.page(work) |> Enum.flat_map(& &1.blocks) |> Enum.map(& &1.ref)`; `[a, b | _] = split(section.body)`; `for ref <- Rewrite.covered_refs(section, a <> "\n\n" <> b) do assert ref in page_refs, "a ref the page never renders dims nothing" end`. (1 source assertion, in a loop over two refs)
(Describe total: 8)

Behavior not obvious from the code:
- Length limit: span of more than 2,500 words -> `{:error, {:span_too_long, words, 2500}}`. Spans at or below the limit proceed to locate the span in the draft and return `{:error, :not_in_draft}` if absent, before any LLM call (this is why no provider is needed).
- answer_budget: floor 3000 for short spans; at least words*3*1.4 for long; answer_budget(2500 words) + reasoning_headroom(:deepseek) must be <= 65_536.
- span_label counts whitespace-separated words ("word " x 1050 -> "Rewrites of 1050 words"); a short selection -> "Rewrites of one line"; the threshold between them is not pinned (5 words -> one line, 1050 -> N words). nil or "" -> "Rewrites".
- span_extent: nil for short spans and nil input; for long spans head + "…" + tail, under 200 chars, no newlines.
- place/3 replaces only the first occurrence and returns `:not_here` rather than the candidate when the span is absent (regression: previously one click destroyed an unselected paragraph).
- covered_refs includes a paragraph merely overlapped by the start of the span, and the refs equal the page's own block refs.
- Assertions recorded: 9 + 2 + 7 + 9 + 12 + 6 + 8 = 53.

---

## test/marginalia/apply_rewrite_test.exs  (5 tests; covers Marginalia.Works.replace_block/3,4, Works.revisions/1, Works.replay/1)

`use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; `alias Marginalia.Works`. Moduledoc: replacing a passage with a rewrite of it, whatever it spans; "This was refused for anything crossing a paragraph boundary, on the grounds that the editor writes one paragraph at a time. The editor does; `Works.replace_block/4` does not -- it replaces any substring of the section body, so a span across four paragraphs was replaceable the whole time."
Setup:
```
user = user_fixture()
body =
  "# One\n\nALPHA the first paragraph. " <> String.duplicate("word ", 120) <>
  "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120) <>
  "\n\nCHARLIE the third paragraph. " <> String.duplicate("word ", 120)
{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
%{user: user, work: work, section: hd(Works.list_sections(work.id))}
```
Helper `span_across_two(section)`: `section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.drop_while(&(&1 =~ "# One"))` then `[a, b | _]`; returns `a <> "\n\n" <> b` (the ALPHA paragraph, blank line, the BRAVO paragraph).

### test "a span crossing two paragraphs is replaced whole"
`span = span_across_two(ctx.section)`; assert `String.contains?(ctx.section.body, span)`.
`{:ok, _} = Works.replace_block(ctx.section, span, "ONE SENTENCE INSTEAD OF BOTH.", origin: "rewrite")` (arity 4, keyword opts). `body = Repo.reload!(ctx.work).body`.
Assertions (5 including the contains): `body =~ "ONE SENTENCE INSTEAD OF BOTH."`; `refute body =~ "ALPHA the first paragraph."`; `refute body =~ "BRAVO the second paragraph."`; `body =~ "CHARLIE the third paragraph."` ("the paragraph after it is untouched").

### test "it records one revision, so the replacement is undoable"
`Works.replace_block(ctx.section, span, "A SHORTER VERSION.", origin: "rewrite", note: "cuts the gloss")` -> `{:ok, _}`.
Assertions (6): `assert [rev] = Works.revisions(ctx.work.id)` (exactly one revision); `rev.origin == "rewrite"`; `rev.note == "cuts the gloss"`; `rev.before =~ "ALPHA"`; `rev.before =~ "BRAVO"` ("the whole passage is what was replaced"); `rev.after == "A SHORTER VERSION."`.

### test "replaying the history reproduces the draft after a multi-paragraph replace"
After replace_block (origin "rewrite", text "A SHORTER VERSION."): assertions (2): `assert {:ok, replayed} = Works.replay(ctx.work.id)`; `replayed == Repo.reload!(ctx.work).body`.

### test "a passage that has changed underneath is refused rather than guessed at"
`span = span_across_two(ctx.section)`. Somebody edits one paragraph first: `first = ctx.section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))`; `{:ok, %{section: moved}} = Works.replace_block(ctx.section, first, "REWRITTEN ALREADY.")` (no opts; returns `{:ok, %{section: updated_section, ...}}`).
Assertions (2): `Works.replace_block(moved, span, "TOO LATE.") == {:error, :moved}`; `refute Repo.reload!(ctx.work).body =~ "TOO LATE."`.

### test "an empty replacement is refused: a deletion is not a rewrite"
assert `Works.replace_block(ctx.section, span, "   ") == {:error, :empty}`. (1)

Behavior not obvious from the code:
- replace_block replaces any substring of the section body (not only one paragraph); stale span -> `{:error, :moved}`; blank/whitespace replacement -> `{:error, :empty}`.
- A revision row records origin, note, before (the whole passage), after; `Works.replay/1` returns `{:ok, body}` equal to the live body.
- Assertions recorded: 5 + 6 + 2 + 2 + 1 = 16.

---

## test/marginalia/revisions_test.exs  (11 tests; covers Marginalia.Works revision history: replace_block/3,4, revisions/1, revision_count/1, baseline/1, replay/1, get_work/2; and Marginalia.Diff.rows/2, any?/1, stat/1)

`use Marginalia.DataCase, async: true`; `import Marginalia.AccountsFixtures`; `alias Marginalia.Works`. Moduledoc: "The history of a draft's prose, and the property it has to keep. Patches applied in order over the baseline reproduce the body. If that ever stops being true the diff view is showing something that is not the draft, so it is asserted here rather than assumed."
Setup:
```
user = user_fixture()
body =
  "# A draft\n\nALPHA the first paragraph. " <> String.duplicate("word ", 120) <>
  "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)
{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
%{user: user, work: work, section: hd(Works.list_sections(work.id))}
```
Helper `block(section, lead)`: `section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&String.contains?(&1, lead))` (the paragraph containing `lead`).
No LLM, no put_env.

### test "the baseline is captured when the draft arrives"
Assertions (2): `work.baseline_body == work.body`; `Works.baseline(work) == work.body`. (So create_work stores `baseline_body` on the work row.)

### test "an edit records one revision"
`b = block(section, "ALPHA")`; `{:ok, _} = Works.replace_block(section, b, String.replace(b, "ALPHA", "AMENDED"))` (no opts).
Assertions (6): `assert [rev] = Works.revisions(work.id)`; `rev.seq == 1`; `rev.origin == "edit"` (default origin); `rev.before =~ "ALPHA"`; `rev.after =~ "AMENDED"`; `rev.section_ordinal == section.ordinal`.

### test "a rewrite says so, and carries the candidate's label"
`b = block(section, "BRAVO")`; `{:ok, _} = Works.replace_block(section, b, String.replace(b, "BRAVO", "BETTER"), origin: "rewrite", note: "cuts the gloss")`.
Assertions (3): `assert [rev] = Works.revisions(work.id)`; `rev.origin == "rewrite"`; `rev.note == "cuts the gloss"`.

### test "replaying every patch over the baseline reproduces the body"
```
b1 = block(section, "ALPHA")
{:ok, %{section: section}} = Works.replace_block(section, b1, String.replace(b1, "ALPHA", "ONE"))
b2 = block(section, "BRAVO")      # uses the returned (updated) section
{:ok, _} = Works.replace_block(section, b2, String.replace(b2, "BRAVO", "TWO"))
```
Assertions (3): `assert {:ok, replayed} = Works.replay(work.id)`; `replayed == Repo.reload!(work).body`; `Works.revision_count(work.id) == 2`.

### test "seq is per work and does not skip"
```
for lead <- ["ALPHA", "BRAVO"] do
  section = Repo.reload!(section)           # section reloaded each iteration
  b = block(section, lead)
  {:ok, _} = Works.replace_block(section, b, String.replace(b, lead, lead <> "!"))
end
```
Assertion (1): `Enum.map(Works.revisions(work.id), & &1.seq) == [1, 2]` (revisions/1 returns oldest first / ascending seq).

### test "an edit that changes nothing records nothing"
`b = block(section, "ALPHA")`; `{:ok, %{superseded: 0}} = Works.replace_block(section, b, b)` (identical replacement still returns `{:ok, map}` where map has `superseded: 0`).
Assertion (1): `Works.revisions(work.id) == []`.

### test "a draft from before any history still has a baseline"
`stripped = %{work | baseline_body: nil}`; assert `Works.baseline(stripped) == work.body` (no revisions -> falls back to the body). (1)

### describe "a draft from before the baseline column existed"

#### test "the baseline is reconstructed from the revisions rather than the body"
```
b = block(section, "ALPHA")
{:ok, _} = Works.replace_block(section, b, String.replace(b, "ALPHA", "AMENDED"))
# what those drafts look like: history, no stored baseline
{:ok, _} = work |> Ecto.Changeset.change(baseline_body: nil) |> Repo.update()
work = Repo.reload!(work)
baseline = Works.baseline(work)
```
Assertions (3): `baseline =~ "ALPHA"` message "the text that was replaced has to come back"; `refute baseline =~ "AMENDED"`; `refute baseline == work.body` message "falling back to the body makes the draft diff against itself and report no changes".

#### test "the reconstructed baseline actually diffs"
```
b = block(section, "BRAVO")
{:ok, _} = Works.replace_block(section, b, String.replace(b, "BRAVO", "BETTER"))
{:ok, _} = work |> Ecto.Changeset.change(baseline_body: nil) |> Repo.update()
work = Repo.reload!(work)
rows = Marginalia.Diff.rows(Works.baseline(work), work.body)
```
Assertions (2): `Marginalia.Diff.any?(rows)`; `Marginalia.Diff.stat(rows).changed == 1`.

#### test "a stored baseline is still preferred over reconstructing one"
assert `Works.baseline(work) == work.baseline_body` (1) (no edits, stored baseline present).

### test "an edit is stored one sentence per line, and the replay still holds"
```
b = block(section, "ALPHA")
typed = "ALPHA was rewritten. It came back\nwrapped, as pasted text does. Two sentences became three."
{:ok, %{section: section}} = Works.replace_block(section, b, typed)
```
Assertions (3):
1. `section.body =~ "ALPHA was rewritten.\nIt came back wrapped, as pasted text does.\nTwo sentences became three."` (returned section's body: the typed text is re-flowed to one sentence per line, the soft wrap "back\nwrapped" is joined to "back wrapped", sentence boundaries become "\n")
2. `[rev] = Works.revisions(work.id)` then `rev.after == "ALPHA was rewritten.\nIt came back wrapped, as pasted text does.\nTwo sentences became three."` (revision stores the normalised text)
3. `work = Works.get_work(work.user_id, work.id)` (get_work/2: user_id, work_id); `replayed = Enum.reduce(Works.revisions(work.id), Works.baseline(work), fn r, body -> String.replace(body, r.before, r.after, global: false) end)`; `assert replayed == work.body`.

Behavior not obvious from the code:
- Baseline: stored in `works.baseline_body` at create time. When it is nil on an old draft, `baseline/1` reconstructs it from revisions (undoing patches from the body, i.e. restoring `before` text) and only falls back to the body when there are no revisions. A stored baseline always wins.
- Revisions: `seq` is 1-based and per work, no gaps; default origin is "edit"; `section_ordinal` recorded. An identical replacement records nothing and returns `{:ok, %{superseded: 0, ...}}`.
- `replay` is (baseline with each revision's `before` replaced by `after`, first occurrence only, in seq order) and must equal the body; the test applies that same rule by hand in the last test.
- Draft text is normalised to one sentence per line on every edit (commit "drafts: one sentence per line, on arrival and on every edit").
- Assertions recorded: 2 + 6 + 3 + 3 + 1 + 1 + 1 + 3 + 2 + 1 + 3 = 26.

---

## test/marginalia/runs_test.exs  (9 tests; covers Marginalia.Runs: start/3, get/1, running?/1, forget/1, subscribe/1, progress/2)

`use ExUnit.Case, async: false` (no DB). `alias Marginalia.Runs`. Moduledoc: "Work that outlives the page that asked for it. The thing being tested is a negative: that killing the process which started a run does not kill the run. That was the behaviour of `start_async/3` in a LiveView, where the task is linked to the socket, and it meant a dropped websocket destroyed a forward read of a hundred and forty-seven documents -- two hours of sequential model calls, already paid for, gone because somebody's wifi blinked."
Setup: `key = {:test, System.unique_integer([:positive])}`; `on_exit(fn -> Runs.forget(key) end)`; context `%{key: key}`. Keys are arbitrary terms (tuples).
Helper `held(key, kind)`: starts a run whose function does:
```
send(me, {:running, self()})
receive do
  {:finish, value} -> value          # the run's return value
  :crash -> raise "asked to crash"
after
  5_000 -> :timed_out
end
```
`{:ok, _} = Runs.start(key, kind, fun)`, then `assert_receive {:running, pid}, 1_000` and returns the worker pid (that assert_receive is inside the helper; it runs once per use of held/2: used in 8 tests -- not counted below).
Runs.start/3 return: `{:ok, something}` or `{:error, {:already_running, kind}}`. `Runs.get(key)` returns a map with at least `:kind`, `:done` (starts 0), `:total`, `:stage` -- or nil when nothing is running.
Process-level: the worker is a process independent of the caller (a Task under Marginalia.TaskSupervisor, per the project memory note; not linked to the caller).

### test "the run survives the process that started it"
```
me = self()
starter = spawn(fn ->
  {:ok, _} = Runs.start(key, :read, fn ->
    send(me, {:running, self()})
    receive do: ({:finish, v} -> v), after: (5_000 -> :timed_out)
  end)
  send(me, :started)
  receive do: (:never -> :ok)
end)
assert_receive :started, 1_000
assert_receive {:running, worker}, 1_000
Process.exit(starter, :kill)
refute Process.alive?(starter)
# the point of the whole module
Process.sleep(50)
assert Process.alive?(worker), "killing the starter must not take the work with it"
assert %{kind: :read} = Runs.get(key)
send(worker, {:finish, :done})
Process.sleep(50)
refute Runs.running?(key)
```
Assertions (6): assert_receive :started (1000ms); assert_receive {:running, worker} (1000ms); `refute Process.alive?(starter)`; `assert Process.alive?(worker)`; `assert %{kind: :read} = Runs.get(key)`; `refute Runs.running?(key)` (after 50 ms the finished run is no longer running).

### test "a page that arrives late finds the run in flight"
`worker = held(key, :compose)`. Comment: "what a fresh mount does". Assertions (2): `assert %{kind: :compose, done: 0} = Runs.get(key)`; `assert Runs.running?(key)`. Then `send(worker, {:finish, :ok})`.

### test "a second run on the same key is refused by name"
`worker = held(key, :read)`. Assertions (2): `assert {:error, {:already_running, :read}} = Runs.start(key, :deepen, fn -> :ok end)`; `assert {:error, {:already_running, :read}} = Runs.start(key, :read, fn -> :ok end)` (the error names the kind of the run already in flight, not the one requested). Then finish the worker.

### test "another key is not blocked by this one"
`other = {:test, System.unique_integer([:positive])}`; `on_exit(fn -> Runs.forget(other) end)`; `worker = held(key, :read)`. Assertion (1): `assert {:ok, _} = Runs.start(other, :read, fn -> :ok end)`. Then finish worker.

### describe "what subscribers hear"
setup: `Runs.subscribe(key)` (subscribes the test process, PubSub-style, to messages for that key); returns :ok. Messages are plain messages to the subscriber: `{:run, :started, info}`, `{:run, :progress, info}`, `{:run, :done, kind, result}`, `{:run, :crashed, kind, reason}`.

#### test "started, then progress, then done"
```
worker = held(key, :read)
assert_receive {:run, :started, %{kind: :read, done: 0}}
Runs.progress(key, done: 3, total: 12)
assert_receive {:run, :progress, %{done: 3, total: 12}}
assert %{done: 3, total: 12} = Runs.get(key)
send(worker, {:finish, {:errors, 0}})
assert_receive {:run, :done, :read, {:errors, 0}}
refute Runs.running?(key)
```
Assertions (5): the 3 assert_receive, `assert %{done: 3, total: 12} = Runs.get(key)`, `refute Runs.running?(key)` (immediately after the :done message, the key must already be free). The worker's return value is delivered as the fourth element.

#### test "a stage, for work that has no count to report"
```
worker = held(key, :compose)
assert_receive {:run, :started, _}
Runs.progress(key, stage: "outlining")
assert_receive {:run, :progress, %{stage: "outlining"}}
Runs.progress(key, stage: "writing", done: 2, total: 5)
assert_receive {:run, :progress, %{stage: "writing", done: 2, total: 5}}
send(worker, {:finish, :ok})
assert_receive {:run, :done, :compose, :ok}
```
Assertions (4 assert_receive).

#### test "a crash is announced and the key is freed"
```
worker = held(key, :read)
assert_receive {:run, :started, _}
send(worker, :crash)
assert_receive {:run, :crashed, :read, _reason}, 2_000
refute Runs.running?(key)
# and the folder is not wedged afterwards
assert {:ok, _} = Runs.start(key, :read, fn -> :ok end)
```
Assertions (4): two assert_receive (the second with a 2000 ms timeout), `refute Runs.running?(key)`, `assert {:ok, _} = Runs.start(...)`.

#### test "progress for a key with nothing running is dropped, not stored"
`Runs.progress(key, done: 9)` (no run started). Assertions (2): `refute_receive {:run, :progress, _}, 100`; `assert Runs.get(key) == nil`.

### test "an error returned by the work reaches the page as a value"  (not in the describe; subscribes inline)
`Runs.subscribe(key)`; `worker = held(key, :compose)`; `send(worker, {:finish, {:error, :not_read}})`. Assertion (1): `assert_receive {:run, :done, :compose, {:error, :not_read}}` (an error tuple returned by the function is a normal :done result, not :crashed).

Behavior not obvious from the code:
- A run is not linked to its starter: the starter process being `:kill`ed must leave the worker alive and `Runs.get(key)` still returning `%{kind: :read}`.
- Only one run per key at a time; the refusal reports the kind of the running one. Other keys are independent.
- On normal completion the key is cleared (running? false) before/at the time `{:run, :done, ...}` is delivered; on crash (raise inside the function) `{:run, :crashed, kind, reason}` is delivered and the key is freed so another run may start.
- `progress/2` merges keyword fields (`done`, `total`, `stage`) into the stored info and broadcasts them; for a key with no run it does nothing: no broadcast, nothing stored.
- Assertions recorded: 6 + 2 + 2 + 1 + 5 + 4 + 4 + 2 + 1 = 27 (assert_receive/refute_receive counted).

---

## test/marginalia/recovery_test.exs  (4 tests; covers Marginalia.Recovery.sweep/0 with Marginalia.Links and Marginalia.Works)

`use Marginalia.DataCase, async: false`; `import Marginalia.AccountsFixtures`; `alias Marginalia.{Links, Recovery, Works}`. Moduledoc: "A deploy went out while twelve links were running. Every one of them died with the container and every row went on saying "linking" for ever."
Setup: `user = user_fixture()`; `mk = fn t -> {:ok, w} = Works.create_work(user.id, %{"title" => t, "body" => String.duplicate("word ", 300)}); w end`; returns `%{a: mk.("One"), b: mk.("Two"), c: mk.("Three")}`.
`Recovery.sweep/0` returns a 2-tuple `{links_failed_count, works_failed_count}`.

### test "a link left mid-run is marked failed, with the reason"
`{:ok, link} = Links.get_or_create(a.id, b.id)`; `{:ok, _} = Links.set_status(link, "linking")`.
Assertions (3): `assert {1, _} = Recovery.sweep()`; `link = Links.get(link.id)`; `link.status == "failed"`; `link.error =~ "restart"` (the error text contains the substring "restart").

### test "a read left mid-run is too"
`{:ok, _} = Works.set_status(c, "reading")`. Assertions (2): `assert {_, 1} = Recovery.sweep()`; `Repo.reload!(c).status == "failed"`.

### test "it leaves finished work alone"
```
{:ok, link} = Links.get_or_create(a.id, b.id)
{:ok, _} = Links.set_status(link, "linked", %{summary: "Done."})   # set_status/3 with extra attrs
{:ok, _} = Works.set_status(c, "read")
```
Assertions (4): `assert {0, 0} = Recovery.sweep()`; `Links.get(link.id).status == "linked"`; `Links.get(link.id).summary == "Done."`; `Repo.reload!(c).status == "read"`.

### test "nothing in flight is a no-op"
assert `{0, 0} = Recovery.sweep()` (1). (The setup has created three works with default status, which are untouched.)

Behavior not obvious from the code:
- Statuses swept: link "linking" -> "failed" with error text including "restart"; work "reading" -> "failed". "linked" and "read" statuses (and default statuses) are untouched.
- The sweep runs at endpoint start (see the repo commit "Recover interrupted runs before the endpoint serves"); the test calls it directly.
- `async: false` because sweep touches every row in the table.
- Assertions recorded: 3 + 2 + 4 + 1 = 10.

---

## test/marginalia/prompts_test.exs  (7 tests; covers the prompt text of every LLM pass: Analysis.passes/0, Linker.passes/0, Weave.passes/0, Rewrite.passes/0, DecisionGraph.passes/0, Links.Chat.passes/0, Cases.Chat.passes/0, Linker.prompt/0, Chat.Editor.system_prompt/0, and source files lib/marginalia/summary.ex, lib/marginalia/document.ex)

`use ExUnit.Case, async: true` (no DB). Aliases `Marginalia.{Analysis, Rewrite}` and `Marginalia.Analysis.{DecisionGraph, Linker, Weave}`.
Moduledoc: "What every pass is told, checked for the things a prompt teaches by accident. A prompt's examples are not illustrations, they are the format. The beats pass said to write a title as "He sets June 2020 as the baseline", and so every beat in the database says "He shows", "He reduces", "He makes" -- of writers nobody has ever met and whose gender no draft states. One word in one example, thousands of rows downstream. Nothing else in the system would ever have failed over it, which is what this file is for."
These tests do NOT call an LLM. They assert on the literal text of the prompts the pipeline ships, so the new implementation must carry prompts that satisfy them (a rewrite must port the prompts, or write equivalents, with these properties).

Helper `all_passes/0` = `Analysis.passes() ++ Linker.passes() ++ Weave.passes() ++ Rewrite.passes() ++ DecisionGraph.passes() ++ Marginalia.Links.Chat.passes() ++ Marginalia.Cases.Chat.passes()`. Each pass is a map with keys `:id`, `:name`, `:model`, `:runs`, `:produces`, `:prompt`. In the current code the ids are: "beats", "spine" (Analysis, plus Weave's passes appended by Analysis.passes/0, so "weave" appears in Analysis.passes too and in the list twice), "link" (Linker), "weave" (Weave), "rewrite" (Rewrite), "narratives" and "decision_graph" (DecisionGraph), "link_chat" (Links.Chat), "case_chat" (Cases.Chat). Note `Analysis.passes()` already includes `Weave.passes()`, so Weave's pass is listed twice in all_passes.

Module attributes:
- `@gendered ~r/\b(he|him|his|she|her|hers)\b/i`
- `@rule ~r/never assume anyone's gender/i`

Comment on the "pronouns" describe: "The rule is not "always they" -- that would flatten a character the manuscript has already told you about. It is: never *assume*. A pronoun is a fact to be read off the page, like any other, and the prompts are where the difference gets taught or lost."

### describe "pronouns"

#### test "a prompt may use a gendered pronoun only if it also says not to assume"
Comment: "An example like "quote what she has said elsewhere" is legitimate -- the writer asking the question already said "she". What is not legitimate is a prompt that shows one without ever stating where a pronoun is supposed to come from, which is how the beats pass came to describe 3,537 writers as "he"."
Computation: for every pass in all_passes, `prompt = pass.prompt || ""`; if `prompt =~ @gendered` and NOT `prompt =~ @rule`, collect `"#{pass.id}: #{hits joined by ", "}"` (hits = unique regex matches).
Assertion (1): `offenders == []` with message "these prompts model a pronoun without saying where one comes from, and every row they produce inherits the guess:\n  " <> offenders joined by "\n  ". A nil prompt counts as "".
Net requirement: every pass prompt that contains any of he/him/his/she/her/hers (whole word, case-insensitive) must also contain the phrase "never assume anyone's gender" (case-insensitive).

#### test "the passes that write about the writer state the rule outright"
For `id <- ["beats", "link"]`: `pass = Enum.find(all_passes(), &(&1.id == id))`.
Assertions (2 source, 4 executed): `assert pass, "#{id} is a pass that names the writer, and it is missing"`; `assert pass.prompt =~ @rule, "#{id} shows the convention but never states it; the next edit to the example silently undoes it"`.
Net requirement: passes with ids "beats" and "link" exist, and their prompts contain "never assume anyone's gender" (case-insensitive).

#### test "the beats prompt shows the writer as they, since the example is the format"
`beats = Enum.find(all_passes(), &(&1.id == "beats"))`. Assertions (2): `beats.prompt =~ "They set June 2020 as the baseline"` (exact, case-sensitive); `refute beats.prompt =~ ~r/\bHe sets\b/` (case-sensitive: "He sets" must not appear).

#### test "the rule covers characters as well as the writer"
Assertion (1): `beats.prompt =~ ~r/calls her she/i` with message "a character the draft has already gendered keeps those pronouns". (So the beats prompt contains a phrase such as "if the draft calls her she" in some casing.)

#### test "the passes that are not in the pass list are covered too"
Comment: "`Summary` and `Document` have no `passes/0` -- they are reached from the Read tab rather than the pass list, which is exactly how they would have been missed. Read from source, since neither exposes its prompt."
For `file <- ["lib/marginalia/summary.ex", "lib/marginalia/document.ex"]` (paths relative to the process cwd = project root): `for [_, body] <- Regex.scan(~r/@prompt """\n(.*?)\n  """/s, File.read!(file))` -> `assert not (body =~ @gendered) or body =~ @rule, "#{file} models a gendered pronoun without stating the rule"`.
Assertions: 1 source. In the current code summary.ex has exactly one `@prompt """` heredoc (line 87) so it runs once; document.ex has no `@prompt """` (it names `@compose_prompt` and `@guide_prompt`, which this regex does not match), so that file contributes zero iterations. `File.read!` of both paths must succeed (a missing file crashes the test). For a non-Elixir rewrite, this test has no direct equivalent unless the files exist; the property to carry over is: the summary prompt, if it uses a gendered pronoun, states the rule.

#### test "the editor, which talks about characters most, carries the rule"
Comment: "Not a `passes/0` entry either, and the one prompt where following a stated pronoun actually comes up every conversation."
Assertion (1): `Marginalia.Chat.Editor.system_prompt() =~ @rule` (system_prompt/0, arity 0, returns a string containing "never assume anyone's gender", case-insensitive).

### describe "the linker's naming convention"

#### test "it requires the full form, because a bare letter cannot be resolved"
Comment: "`Links.plain/2` substitutes the real titles in. A lone "A" is indistinguishable from the article, so the prompt has to stop producing them rather than the substitution having to guess."
Assertions (2): `Linker.prompt() =~ "Never a bare"` (exact, case-sensitive); `Linker.prompt() =~ ~r/Manuscript A.*IN FULL|IN FULL.*Manuscript/s` (dot matches newlines: the prompt has "Manuscript A" followed later by "IN FULL", or "IN FULL" followed later by "Manuscript").

Behavior not obvious from the code:
- Everything here is about prompt wording; the pass list must expose ids "beats" and "link" with a `:prompt` string.
- The pronoun rule is "never assume anyone's gender" as a verbatim phrase (regex is case-insensitive, apostrophe is the ASCII `'`).
- Assertions recorded: 1 + 2 + 2 + 1 + 1 + 1 + 2 = 10 (source count; the for-loops execute more).

---

## test/marginalia/provider_gate_test.exs  (20 tests; covers Marginalia.Accounts.owner?/1, provider_for/1, set_llm_provider/2; Marginalia.LLM.provider_name/0, default_model/0,1, reasoning_effort/1, reasoning_headroom/1, token_budget/2, label/1, available/0, choices/0, configured?/1; Marginalia.Analysis.passes/0, DecisionGraph.passes/0)

`use Marginalia.DataCase, async: true`; aliases `Marginalia.{Accounts, LLM}`; `import Marginalia.AccountsFixtures`. Moduledoc: "Only the owner may choose the model backend -- one account, by email, and nobody else including admins. The gate is in the context rather than in the template, so a crafted form post cannot reach past it."
Helpers:
- `owner/0`: `email = Application.get_env(:marginalia, :owner_email)`; `user_fixture() |> Ecto.Changeset.change(email: email) |> Marginalia.Repo.update!()`. Comment: "build a real user whose email is whatever this deploy calls the owner, so the test never has to mutate global config". (Application env `:owner_email` is set in config/runtime.exs: `System.get_env("OWNER_EMAIL", "bobbbygrayson@gmail.com")`; it is not overridden in config/test.exs, so in test it is "bobbbygrayson@gmail.com" unless OWNER_EMAIL is set.)
- `admin(user)`: `user |> Ecto.Changeset.change(is_admin: true) |> Marginalia.Repo.update!()`.
No put_env, no LLM calls, no network. API keys are nil in test (config/test.exs: `:deepseek_api_key` and `:openai_api_key` nil).

### describe "owner?/1"
#### test "the configured email is the owner"
assert `Accounts.owner?(owner())`. (1)
#### test "case does not decide who owns the account"
`email = Application.get_env(:marginalia, :owner_email) |> String.upcase()`; assert `Accounts.owner?(%{user_fixture() | email: email})` (a struct updated in memory, not persisted; comparison is case-insensitive). (1)
#### test "an admin who is not the owner is not the owner"
refute `Accounts.owner?(admin(user_fixture()))`. (1)

### describe "provider_for/1"   (returns nil for "use the deploy default", else the provider string)
#### test "a normal user always gets the deploy default, even with a value on the row"
`user = %{user_fixture() | llm_provider: "openai"}`; assert `Accounts.provider_for(user) == nil`. (1)
#### test "being an admin is not enough -- the switch is the owner's alone"
`user = %{admin(user_fixture()) | llm_provider: "openai"}`; assert `Accounts.provider_for(user) == nil`. (1)
#### test "the owner gets their chosen backend"
assert `Accounts.provider_for(%{owner() | llm_provider: "openai"}) == "openai"`. (1)
#### test "the owner who has chosen nothing gets the deploy default"
assert `Accounts.provider_for(%{owner() | llm_provider: nil}) == nil`. (1)

### describe "set_llm_provider/2"   (user, provider string -> {:ok, user} | {:error, :unknown_provider})
#### test "a normal user's attempt is a no-op, not an error they can probe"
`user = user_fixture()`. Assertions (3): `assert {:ok, same} = Accounts.set_llm_provider(user, "openai")`; `same.llm_provider == nil`; `Marginalia.Repo.reload!(user).llm_provider == nil`.
#### test "an admin's attempt is also a no-op"
`user = admin(user_fixture())`. Assertions (2): `assert {:ok, _} = Accounts.set_llm_provider(user, "openai")`; `Repo.reload!(user).llm_provider == nil`.
#### test "the owner can switch, and it persists"
`user = owner()`. Assertions (3): `assert {:ok, updated} = Accounts.set_llm_provider(user, "openai")`; `updated.llm_provider == "openai"`; `Accounts.provider_for(Repo.reload!(user)) == "openai"`.
#### test "an unknown backend is refused rather than stored"
`user = owner()`. Assertions (2): `assert {:error, :unknown_provider} = Accounts.set_llm_provider(user, "definitely-not-a-provider")`; `Repo.reload!(user).llm_provider == nil`.

### describe "the two backends on offer"
#### test "defaults to deepseek for this deploy"
assert `LLM.provider_name() == :deepseek` (app env `:llm_provider` unset in test; default "deepseek"). (1)

#### test "each provider names a real model"   (comment above: "these are the ids the providers' own /models endpoints return")
Assertions (2): `LLM.default_model("deepseek") == "deepseek-flash"`; `LLM.default_model("openai") == "gpt-5.6-sol"` (requires `:llm_model` app env unset).

#### test "the default effort is low, with room to think reserved either way"
Comments above it: "the regression that broke every read: reasoning tokens are spent before any content, so the request budget has to cover thinking on top of the answer the caller asked for" and "reasoning tokens are billed as output and never cached, so the default is cheap and the passes that reason over a whole draft opt up".
`for name <- LLM.available()` (atoms :deepseek and :openai): assertions (2 source, 4 executed): `LLM.reasoning_effort(name) == "low"`; `LLM.reasoning_headroom(name) > 0` (the real values are 24_000 for both).

#### test "only the whole-draft passes ask for high effort"
`by_effort = (Marginalia.Analysis.passes() ++ Marginalia.Analysis.DecisionGraph.passes()) |> Enum.map(& &1.id)`. Comment: "the per-section pass is most of the calls in a read; it stays cheap". Assertions (3): `"beats" in by_effort`; `"spine" in by_effort`; `"weave" in by_effort`. (Despite the name, it asserts only membership of the ids; "weave" appears because Analysis.passes/0 appends Weave.passes/0.) Nothing here inspects an effort value.

#### test "the sent budget is the caller's ask plus room to think"
Assertions (2): `LLM.token_budget(:deepseek, 4_000) == 4_000 + LLM.reasoning_headroom(:deepseek)` (= 28_000); `LLM.token_budget(:deepseek, nil) == nil` (nil stays nil).

#### test "each provider has a label a person would recognise"
Assertions (2): `LLM.label("deepseek") == "DeepSeek Flash"`; `LLM.label("openai") == "Sol 5"`.

#### test "a junk override falls back rather than wedging the account"
assert `LLM.default_model("nonsense") == LLM.default_model()` (unknown provider string resolves to the deploy default). (1)

#### test "both providers are known to this deploy"
Assertions (2): `:deepseek in LLM.available()`; `:openai in LLM.available()`.

#### test "choices/0 offers only backends that actually have a key"
`for choice <- LLM.choices()`: assertions (3 source): `LLM.configured?(choice.name)`; `choice.label != nil`; `choice.model != nil`. In the test environment both API keys are nil, so `choices()` is `[]` and the loop body never runs; this test passes vacuously. Choices have shape `%{name:, label:, model:}` sorted by label; a provider with no key is omitted.

Behavior not obvious from the code:
- Gate: only a user whose email equals (case-insensitively) the deploy's owner email is "owner"; admin flag grants nothing. `provider_for` returns nil unless owner AND the row's `llm_provider` is set. `set_llm_provider` for a non-owner returns `{:ok, user_unchanged}` (no error, no write) so a probe cannot tell the difference; for the owner an unrecognised string returns `{:error, :unknown_provider}` and writes nothing.
- Provider table in the current code: deepseek (label "DeepSeek Flash", model and fast_model "deepseek-flash", reasoning_effort "low", reasoning_headroom 24_000) and openai (label "Sol 5", model "gpt-5.6-sol", fast_model "gpt-5.4-nano", effort "low", headroom 24_000).
- Assertions recorded: 3 + 4 + 10 + 18 = 35 (backends describe: 1+2+2+3+2+2+1+2+3 = 18).

---

## test/marginalia/quota_test.exs  (7 tests; covers Marginalia.Chat: message_limit/0, remaining/1, allowed?/1, messages_sent/1, append/3, get_or_create_conversation/1; Works.delete_work/1)

`use Marginalia.DataCase, async: true`; aliases `Marginalia.{Chat, Works}`; `import Marginalia.AccountsFixtures`. Moduledoc: "Uploading needs no account, so the model credit is spendable by anyone who finds the site. The cap is what stands between that and a bill."
Setup:
```
user = user_fixture()
{:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => String.duplicate("w ", 300)})
{:ok, convo} = Chat.get_or_create_conversation(work.id)
%{user: user, work: work, convo: convo}
```
Helper `ask(convo, n)`: `for i <- 1..n, do: Chat.append(convo.id, "user", "question #{i}")` (n >= 1).
The current limit is `@message_limit 100` (`Chat.message_limit/0` returns 100; tests use the function, not the literal).

### test "a fresh account has the full allowance"
Assertions (2): `Chat.remaining(user) == Chat.message_limit()`; `Chat.allowed?(user)`.

### test "only the writer's own questions count against it"
`ask(convo, 3)`; `Chat.append(convo.id, "assistant", "an answer, which is not a question")`. Assertions (2): `Chat.messages_sent(user.id) == 3`; `Chat.remaining(user) == Chat.message_limit() - 3`.

### test "it runs out, and does not go negative"
`ask(convo, Chat.message_limit() + 5)` (105 questions). Assertions (2): `Chat.remaining(user) == 0`; `refute Chat.allowed?(user)`.

### test "questions across every draft count together"
Creates a second work for the same user: `Works.create_work(user.id, %{"title" => "Other", "body" => String.duplicate("w ", 300)})` and `Chat.get_or_create_conversation(other.id)`; `ask(convo, 4)`; `ask(other_convo, 6)`. Assertion (1): `Chat.messages_sent(user.id) == 10`.

### test "one account's questions do not count against another's"
`ask(convo, 5)`. Assertion (1): `Chat.remaining(user_fixture()) == Chat.message_limit()` (a different new user).

### test "deleting a draft gives the questions back"
`ask(convo, 7)`. Assertions (2): `Chat.messages_sent(user.id) == 7`; then `Works.delete_work(work)` and `Chat.messages_sent(user.id) == 0` (messages are removed with the work, via cascade).

### test "the owner of the deploy is not capped"
```
owner = user_fixture() |> Ecto.Changeset.change(email: Application.get_env(:marginalia, :owner_email)) |> Marginalia.Repo.update!()
{:ok, w} = Works.create_work(owner.id, %{"title" => "O", "body" => String.duplicate("w ", 300)})
{:ok, c} = Chat.get_or_create_conversation(w.id)
ask(c, Chat.message_limit() + 1)
ask(convo, 1)
```
(`ask(convo, 1)` posts to the setup user's conversation, a different account.) Assertions (2): `Chat.remaining(owner) == :unlimited`; `Chat.allowed?(owner)`.

Behavior not obvious from the code:
- Only messages with role "user" count; counts are per account across all of that account's works; deleting a work removes its messages from the count.
- `remaining/1` is `max(limit - sent, 0)` for ordinary accounts and the atom `:unlimited` for the owner (email equals `:owner_email`, case-insensitively).
- Assertions recorded: 2 + 2 + 2 + 1 + 1 + 2 + 2 = 12.

---

## test/marginalia/cache_test.exs  (7 tests; covers Marginalia.Cache: fetch/2,3, peek/1, invalidate/1, invalidate_all/0)

`use ExUnit.Case, async: false` (no DB); `alias Marginalia.Cache`. Moduledoc: "Holding the public list of pairs in ETS. The cache knows nothing about links: the expensive thing is passed in. That is what lets these run without a database, and it is why the interesting cases -- a miss, an invalidation, an expiry -- are testable at all."
Setup: `Cache.invalidate_all()`; `on_exit(&Cache.invalidate_all/0)`; returns :ok.
API: `Cache.fetch(key, fun)` and `Cache.fetch(key, fun, ttl_ms)` return the fun's result (computing and storing on a miss or after expiry); `Cache.peek(key)` returns `:miss` or `{:ok, value}` and never computes; `Cache.invalidate(key)`; `Cache.invalidate_all()`. Keys are atoms here (`:k`, `:one`, `:two`). The table is an ETS table, public, read without going through the owning process; the cache server process (a GenServer) must be running in the app.
Messaging note: tests use `assert_received` / `refute_received` (non-blocking mailbox checks on the test process) with `send(me, :computed)` inside the computing fun. `send(me, :computed) && [:x]` works because send returns the (truthy) message.

### test "the first call computes and the second does not"
`fun = fn -> send(me, :computed); [:a, :b] end`. Assertions (4): `Cache.fetch(:k, fun) == [:a, :b]`; `assert_received :computed`; `Cache.fetch(:k, fun) == [:a, :b]`; `refute_received :computed` with message "the second call has to come out of the table".

### test "invalidating makes the next call compute again"
`fun = fn -> send(me, :computed) && [:x] end`. `Cache.fetch(:k, fun)`; `assert_received :computed`; `Cache.invalidate(:k)`; `Cache.fetch(:k, fun)`; `assert_received :computed`. Assertions (2).

### test "peek does not compute anything"
Assertions (2): `Cache.peek(:k) == :miss` (before any fetch); after `Cache.fetch(:k, fn -> [:filled] end)`, `Cache.peek(:k) == {:ok, [:filled]}`.

### test "an entry past its ttl is recomputed"
`fun = fn -> send(me, :computed) && [:fresh] end`. `Cache.fetch(:k, fun, 50)` (ttl 50 ms); `assert_received :computed`; `Process.sleep(60)`; `Cache.fetch(:k, fun, 50)`; `assert_received :computed` with message "a missed invalidation must cost staleness until it expires, not until somebody restarts the release". Assertions (2). (Expiry is decided at read time against the ttl supplied to the fetch/entry; 60 ms sleep must exceed a 50 ms ttl.)

### test "an empty result is cached like any other"
`fun = fn -> send(me, :computed) && [] end`. Assertions (4): `Cache.fetch(:k, fun) == []`; `assert_received :computed`; `Cache.fetch(:k, fun) == []`; `refute_received :computed` with message "nothing to show is an answer, and recomputing it is the same cost".

### test "reads do not go through the server process"
`Cache.fetch(:k, fn -> [:x] end)`. Comment: "if a read were a GenServer call, killing the server mid-read would matter; what is asserted here is only that the table is public and readable from a process that has nothing to do with it". `task = Task.async(fn -> Cache.peek(:k) end)`; assert `Task.await(task) == {:ok, [:x]}`. (1)

### test "two keys do not share an entry"
`Cache.fetch(:one, fn -> [:first] end)`; `Cache.fetch(:two, fn -> [:second] end)`. Assertions (4): `peek(:one) == {:ok, [:first]}`; `peek(:two) == {:ok, [:second]}`; after `Cache.invalidate(:one)`: `peek(:one) == :miss`; `peek(:two) == {:ok, [:second]}` with message "invalidating one must not clear the other".

Behavior not obvious from the code:
- Default ttl for fetch/2 is not pinned by tests (only the explicit 50 ms case).
- `[]` is a cacheable value, distinct from a miss.
- Caching is independent of any database; the producer function is only run on miss/expiry/after invalidation.
- Assertions recorded: 4 + 2 + 2 + 2 + 4 + 1 + 4 = 19.

---

## test/marginalia/accounts_test.exs  (33 tests; covers Marginalia.Accounts context: get_user_by_email/1, get_user_by_email_and_password/2, get_user!/1, register_user/1, sudo_mode?/1,2, change_user_email/1, deliver_user_update_email_instructions/3, update_user_email/2, change_user_password/1,3, update_user_password/2, generate_user_session_token/1, get_user_by_session_token/1, delete_user_session_token/1; Accounts.User and Accounts.UserToken schemas)

`use Marginalia.DataCase` (NOT async: default for DataCase here is sync), `alias Marginalia.Accounts`, `import Marginalia.AccountsFixtures`, `alias Marginalia.Accounts.{User, UserToken}`. This is the stock `mix phx.gen.auth` (magic-link generation) test file, trimmed: registration is by email+password and confirms immediately.
Fixtures (test/support/fixtures/accounts_fixtures.ex, `Marginalia.AccountsFixtures`):
- `unique_user_email()` -> `"user#{System.unique_integer()}@example.com"` (the integer may be negative, e.g. "user-576460752303423167@example.com").
- `valid_user_password()` -> `"hello world!"` (12 chars).
- `valid_user_attributes(attrs \\ %{})` -> `Enum.into(attrs, %{email: unique_user_email(), password: valid_user_password()})`.
- `user_fixture(attrs \\ %{})` -> `{:ok, user} = attrs |> valid_user_attributes() |> Accounts.register_user()`; returns user.
- `unconfirmed_user_fixture(attrs)` -> user_fixture then `Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()`.
- `set_password(user)` -> `{:ok, {user, _}} = Accounts.update_user_password(user, %{password: valid_user_password()})`; returns user.
- `extract_user_token(fun)` -> `{:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")`; `[_, token | _] = String.split(captured_email.text_body, "[TOKEN]")`; returns token. So every `deliver_*` function takes a url-builder fun, calls it with the encoded token to make the URL, and returns `{:ok, email}` where `email.text_body` contains that URL (Swoosh Test adapter).
- Others exist (user_scope_fixture, override_token_authenticated_at, generate_user_magic_link_token, offset_user_token, owner_fixture = user with the `:owner_email` address) but are not used by this file. `owner_fixture` is documented: "Trace and Prompts are internals -- how the thing works rather than what it found -- so they are theirs alone."
Database: Ecto SQL sandbox via DataCase; `errors_on/1` (from DataCase) converts a changeset to `%{field => [messages]}`; `get_change/2` is imported from Ecto.Changeset by DataCase.

### describe "get_user_by_email/1"
#### test "does not return the user if the email does not exist"
refute `Accounts.get_user_by_email("unknown@example.com")` (returns nil). (1)
#### test "returns the user if the email exists"
`%{id: id} = user = user_fixture()`; assert `%User{id: ^id} = Accounts.get_user_by_email(user.email)`. (1)

### describe "get_user_by_email_and_password/2"
#### test "does not return the user if the email does not exist"
refute `Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")`. (1)
#### test "does not return the user if the password is not valid"
`user = user_fixture() |> set_password()`; refute `Accounts.get_user_by_email_and_password(user.email, "invalid")`. (1)
#### test "returns the user if the email and password are valid"
`%{id: id} = user = user_fixture() |> set_password()`; assert `%User{id: ^id} = Accounts.get_user_by_email_and_password(user.email, valid_user_password())`. (1)

### describe "get_user!/1"
#### test "raises if id is invalid"
assert_raise `Ecto.NoResultsError` for `Accounts.get_user!(-1)`. (1)
#### test "returns the user with the given id"
`%{id: id} = user = user_fixture()`; assert `%User{id: ^id} = Accounts.get_user!(user.id)`. (1)

### describe "register_user/1"   (attrs map with atom keys -> {:ok, %User{}} | {:error, changeset})
#### test "requires email to be set"
`{:error, changeset} = Accounts.register_user(%{})`; assert `%{email: ["can't be blank"]} = errors_on(changeset)` (partial map match: email errors are exactly the list ["can't be blank"]; other fields' errors, such as password, are allowed). (1)
#### test "validates email when given"
`Accounts.register_user(%{email: "not valid"})`; assert `%{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)` (exactly that single email message). (1)
#### test "validates maximum values for email for security"
`too_long = String.duplicate("db", 100)` (200 chars, no @); `{:error, changeset} = Accounts.register_user(%{email: too_long})`; assert `"should be at most 160 character(s)" in errors_on(changeset).email` (the list may also hold the @-sign message). (1)
#### test "validates email uniqueness"
`%{email: email} = user_fixture()`; `{:error, changeset} = Accounts.register_user(%{email: email})`; assert `"has already been taken" in errors_on(changeset).email`. Comment: "Now try with the uppercased email too, to check that email case is ignored." `Accounts.register_user(%{email: String.upcase(email)})` -> error again, `"has already been taken" in errors_on(changeset).email`. (2). (The uniqueness is case-insensitive; note the unique-constraint error appears only after the DB insert, i.e. register_user must run the insert and map the unique constraint to the message "has already been taken" on `:email`. Note the email contains only lowercase letters, digits, "@", "." and possibly a leading "-" in the integer, so upcase changes letters only.)
#### test "registers users with a password and confirms them immediately"
`email = unique_user_email()`; `{:ok, user} = Accounts.register_user(valid_user_attributes(email: email))`. Assertions (3): `user.email == email`; `is_binary(user.hashed_password)`; `assert user.confirmed_at, "password-only registration has nothing to confirm"` (confirmed_at is set at registration).
#### test "requires a password"
`{:error, changeset} = Accounts.register_user(%{email: unique_user_email()})`; assert `%{password: ["can't be blank"]} = errors_on(changeset)`. (1)
(Describe total: 9 assertions)

### describe "sudo_mode?/2"
#### test "validates the authenticated_at time"
`now = DateTime.utc_now()`. Assertions (5):
1. assert `Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})`
2. assert `Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})`
3. refute `Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})` (default window is 20 minutes)
4. comment "minute override": refute `Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -11, :minute)}, -10)` (second arg is a negative minutes window: -10 means within the last 10 minutes)
5. comment "not authenticated": refute `Accounts.sudo_mode?(%User{})` (authenticated_at nil)

### describe "change_user_email/3"
#### test "returns a user changeset"
Assertions (2): `assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})`; `changeset.required == [:email]`.

### describe "deliver_user_update_email_instructions/3"   (user, current_email, url_fun)
setup: `%{user: user_fixture()}`
#### test "sends token through notification"
```
token = extract_user_token(fn url ->
  Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
end)
{:ok, token} = Base.url_decode64(token, padding: false)
```
Assertions (4): `assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))` (stored token is the SHA-256 of the url-safe-base64 decoded token embedded in the URL); `user_token.user_id == user.id`; `user_token.sent_to == user.email`; `user_token.context == "change:current@example.com"`.

### describe "update_user_email/2"   (user, token -> {:ok, user} | {:error, :transaction_aborted})
setup:
```
user = unconfirmed_user_fixture()
email = unique_user_email()
token = extract_user_token(fn url ->
  Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
end)
%{user: user, token: token, email: email}
```
(So the token's sent_to is the NEW email and its context is "change:<old email>".)
#### test "updates the email with a valid token"
Assertions (4): `assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)`; `changed_user = Repo.get!(User, user.id)`; `changed_user.email != user.email`; `changed_user.email == email`; `refute Repo.get_by(UserToken, user_id: user.id)` (all of the user's tokens in that context are removed after use).
#### test "does not update email with invalid token"
Assertions (3): `Accounts.update_user_email(user, "oops") == {:error, :transaction_aborted}`; `Repo.get!(User, user.id).email == user.email`; `assert Repo.get_by(UserToken, user_id: user.id)` (the token is still there).
#### test "does not update email if user email changed"
Assertions (3): `Accounts.update_user_email(%{user | email: "current@example.com"}, token) == {:error, :transaction_aborted}`; `Repo.get!(User, user.id).email == user.email`; `assert Repo.get_by(UserToken, user_id: user.id)`. (The token's context "change:<old email>" does not match the in-memory user's email.)
#### test "does not update email if token expired"
`{1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])` (exactly one token row exists). Assertions (3): `Accounts.update_user_email(user, token) == {:error, :transaction_aborted}`; `Repo.get!(User, user.id).email == user.email`; `assert Repo.get_by(UserToken, user_id: user.id)`.
(Describe total: 13)

### describe "change_user_password/3"   (user, attrs \\ %{}, opts \\ [])
#### test "returns a user changeset"
Assertions (2): `assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})`; `changeset.required == [:password]`.
#### test "allows fields to be set"
`changeset = Accounts.change_user_password(%User{}, %{"password" => "new valid password"}, hash_password: false)` (string-keyed attrs). Assertions (3): `changeset.valid?`; `get_change(changeset, :password) == "new valid password"`; `is_nil(get_change(changeset, :hashed_password))` (with hash_password: false the hash is not computed).

### describe "update_user_password/2"   (user, attrs -> {:ok, {user, expired_tokens}} | {:error, changeset})
setup: `%{user: user_fixture()}`
#### test "validates password"
`Accounts.update_user_password(user, %{password: "not valid", password_confirmation: "another"})` -> `{:error, changeset}`. Assertion (1): `assert %{password: ["should be at least 12 character(s)"], password_confirmation: ["does not match password"]} = errors_on(changeset)` (each list exactly one message).
#### test "validates maximum values for password for security"
`too_long = String.duplicate("db", 100)`; `{:error, changeset} = Accounts.update_user_password(user, %{password: too_long})`; assert `"should be at most 72 character(s)" in errors_on(changeset).password`. (1)
#### test "updates the password"
`{:ok, {user, expired_tokens}} = Accounts.update_user_password(user, %{password: "new valid password"})`. Assertions (3): `expired_tokens == []` (fixture user has no tokens); `is_nil(user.password)` (the virtual password is cleared on the returned struct); `assert Accounts.get_user_by_email_and_password(user.email, "new valid password")`.
#### test "deletes all tokens for the given user"
`_ = Accounts.generate_user_session_token(user)`; `{:ok, {_, _}} = Accounts.update_user_password(user, %{password: "new valid password"})`; refute `Repo.get_by(UserToken, user_id: user.id)`. (1)
(Describe total: 6)

### describe "generate_user_session_token/1"
setup: `%{user: user_fixture()}`
#### test "generates a token"
`token = Accounts.generate_user_session_token(user)` (returns the raw binary token, stored raw for sessions). Assertions (4): `assert user_token = Repo.get_by(UserToken, token: token)`; `user_token.context == "session"`; `user_token.authenticated_at != nil`; comment "Creating the same token for another user should fail": `assert_raise Ecto.ConstraintError, fn -> Repo.insert!(%UserToken{token: user_token.token, user_id: user_fixture().id, context: "session"}) end` (unique constraint on (context, token), raising Ecto.ConstraintError rather than returning an error).
#### test "duplicates the authenticated_at of given user in new token"
`user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}`; `token = Accounts.generate_user_session_token(user)`. Assertions (3): `assert user_token = Repo.get_by(UserToken, token: token)`; `user_token.authenticated_at == user.authenticated_at` (copied from the user struct, at second precision); `DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt`.

### describe "get_user_by_session_token/1"
setup: `user = user_fixture()`; `token = Accounts.generate_user_session_token(user)`; `%{user: user, token: token}`
#### test "returns user by token"
Assertions (4): `assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)` (a 2-tuple: user and the token's inserted_at); `session_user.id == user.id`; `session_user.authenticated_at != nil` (the returned user struct carries the token's authenticated_at); `token_inserted_at != nil`.
#### test "does not return user for invalid token"
refute `Accounts.get_user_by_session_token("oops")` (nil, no crash). (1)
#### test "does not return user for expired token"
`dt = ~N[2020-01-01 00:00:00]`; `{1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])`; refute `Accounts.get_user_by_session_token(token)` (session tokens expire; validity is based on inserted_at, 14 days in the stock generator; only the 2020 date is exercised). (1)

### describe "delete_user_session_token/1"
#### test "deletes the token"
`user = user_fixture()`; `token = Accounts.generate_user_session_token(user)`. Assertions (2): `Accounts.delete_user_session_token(token) == :ok`; `refute Accounts.get_user_by_session_token(token)`.

### describe "inspect/2 for the User module"
#### test "does not include password"
refute `inspect(%User{password: "123456"}) =~ "password: \"123456\""` (the password field is redacted from `inspect`; it must not render as `password: "123456"`). (1)

Behavior not obvious from the code:
- Email validation messages (verbatim): "can't be blank", "must have the @ sign and no spaces", "should be at most 160 character(s)", "has already been taken"; password messages: "can't be blank", "should be at least 12 character(s)", "should be at most 72 character(s)", "does not match password" (on `password_confirmation`). Uniqueness is case-insensitive (upcased email still collides).
- `register_user` sets `confirmed_at` immediately and stores `hashed_password`; a password is mandatory (a magic-link-only registration was removed). The `Accounts` context still exposes the confirmation/email-change API for unconfirmed users (fixture comment: "The app no longer produces these -- registration confirms immediately -- but `Marginalia.Accounts` still exposes the confirmation API, so its tests need one.").
- Email-change tokens: stored hashed (SHA-256), context `"change:<current email>"`, `sent_to` is the address the token was mailed to; they expire (an `inserted_at` of 2020 invalidates); using one deletes the user's tokens; failure of any kind (bad token, mismatched current email, expiry) returns exactly `{:error, :transaction_aborted}` and leaves the tokens in place.
- `update_user_password` deletes all of the user's tokens (sessions included) and returns them as the second element of `{:ok, {user, expired_tokens}}`.
- Session tokens are stored raw (not hashed), unique per (context, token), carry `authenticated_at`; sudo mode window defaults to 20 minutes and takes a negative-minutes override.
- Assertions recorded: 2 + 3 + 2 + 9 + 5 + 2 + 4 + 13 + 5 + 6 + 7 + 6 + 2 + 1 = 67.

---

TOTALS (counts of assert / refute / assert_* / refute_* / assert_raise calls recorded in each file's section; `for` loops counted once per source assertion; test counts include `test("...")` call form):

| file | tests | assertions |
|---|---|---|
| reading_test.exs | 18 | 42 |
| reading_render_test.exs | 6 | 11 |
| rewrite_test.exs | 30 | 53 |
| apply_rewrite_test.exs | 5 | 16 |
| revisions_test.exs | 11 | 26 |
| runs_test.exs | 9 | 27 |
| recovery_test.exs | 4 | 10 |
| prompts_test.exs | 7 | 10 |
| provider_gate_test.exs | 20 | 35 |
| quota_test.exs | 7 | 12 |
| cache_test.exs | 7 | 19 |
| accounts_test.exs | 33 | 67 |
| total | 157 | 328 |

(Per-file `grep -c '^\s*test "'` gives 16 for reading_test.exs because two tests are written `test("beats alone", ...)` and `test("tensions alone", ...)`; the real count is 18. All others match grep.)

LLM seam summary for these files: none of the 12 files calls an LLM or stubs one. config/test.exs sets `:deepseek_api_key` and `:openai_api_key` to nil, `:llm_endpoints` to `http://127.0.0.1:1/...`, and `:llm_backoff_ms` to 0; rewrite_test only exercises paths that return before any provider call (`{:error, :not_in_draft}` and `{:error, {:span_too_long, ...}}`). No Application.put_env anywhere in these files. LLM-adjacent assertions are about static values of `Marginalia.LLM` (provider table, headroom 24_000, labels, default models) and prompt text.

# PART 5. Web, cases/read/tour/links/works/drafts

# D1: LiveView tests (case index, case page, case read, tour, changes tab, cluster view, confirm gate, draft render, drawer)

Conventions used below: `html =~ "x"` is a substring assertion on the rendered HTML string; `~r{...}` is a regex match. `live(conn, path)` returns `{:ok, view, html}` (initial rendered HTML). All files use `use MarginaliaWeb.ConnCase, async: false`, `import Phoenix.LiveViewTest`, and `import Marginalia.AccountsFixtures` unless noted. LLM calls: none of the files in this part stub an LLM provider; they insert results directly through `Links.set_status`, `Links.store_edges`, `Works.insert_node`, etc. (details per file).

# =====================================================================
# ROUTE GROUP A: /cases (case index) and /cases/:slug (case page)
# =====================================================================

## test/marginalia_web/live/case_index_test.exs  (22 tests; covers the public LiveView at `/cases`, plus `Marginalia.Cases.holding/1`, `Marginalia.Cases.Record.for/1`, `Marginalia.Links.summary/1`)

Module `MarginaliaWeb.CaseIndexTest`. `use MarginaliaWeb.ConnCase, async: false`. Aliases: `Marginalia.{Cases, Links, Works}`, `Marginalia.Analysis.Linker`. Module attribute `@quote "A sentence long enough"`.

Moduledoc: "The front of the micro-site. What is pinned here is what a reader is owed: the record facts, the read pass's own account of the opinion, every document named and sourced, and one real connection before any explanation of what a connection is."

### Shared setup (runs before every test, including those in the describe block)

Setup block `setup %{conn: conn}`:

1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})` (shared sandbox mode, so LiveView processes see the DB rows).
2. `previous_owner = Application.get_env(:marginalia, :owner_email)`; then `Application.put_env(:marginalia, :owner_email, "owner@example.com")`. `on_exit` restores: if previous was `nil` -> `Application.delete_env(:marginalia, :owner_email)`, else `Application.put_env(:marginalia, :owner_email, email)`. Comment: "Restored, not deleted. `delete_env` drops the configured value instead of putting it back, so anything reading `:owner_email` afterwards sees nil rather than what config set — invisible in one run, because ExUnit runs the async readers before these sync modules, and immediately fatal under --repeat-until-failure, which is the tool for finding flakes."
3. `owner = user_fixture(%{email: "owner@example.com"})`.
4. Helper `mk = fn title, role, extra -> ... end`:
   - `body = "# #{title}\n\n#{@quote} to be a section. We hold that the removal power is " <> "the President's alone.\n\n" <> String.duplicate("word ", 200)`
     i.e. `# <title>`, blank line, `A sentence long enough to be a section. We hold that the removal power is the President's alone.`, blank line, then "word " repeated 200 times.
   - `{:ok, w} = Works.create_work(owner.id, %{"title" => title, "body" => body})`
   - `{:ok, w} = Works.set_status(w, "read")`
   - `{:ok, w} = Cases.place(w, "Trump v. Slaughter", role)` (places the work in the collection named "Trump v. Slaughter", slug `trump-v-slaughter`, with the given role)
   - `{:ok, w} = w |> Ecto.Changeset.change(extra) |> Marginalia.Repo.update()` (extra is a map of raw fields set directly on the work row)
   - `s = hd(Works.list_sections(w.id))` (first section)
   - `{:ok, n} = Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in the #{role}", quote: @quote})`
   - returns `{w, n}`.
5. Three works created (title separator is an em dash):
   - `{op, op_n} = mk.("Trump v. Slaughter — Opinion of the Court", "opinion", %{first_impression: "A majority opinion that announces its destination in section one.", source_url: "https://www.supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf"})`
   - `{di, di_n} = mk.("Trump v. Slaughter — Dissent (Sotomayor)", "dissent", %{})`
   - `{ar, ar_n} = mk.("Trump v. Slaughter — Argument: Gen. D. John Sauer", "argument", %{})`
6. Link 1 (opinion vs dissent): `{:ok, l} = Links.get_or_create(op.id, di.id)`; `{:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree about removal."})`; then `Links.store_edges(l, [%{"from" => op_n.id, "to" => di_n.id, "type" => "tension", "why" => "The Court grounds removal in the Framers' single executive; the dissent finds no founding-era support for it."}], Linker.types())`.
7. Link 2 (opinion vs argument): `{:ok, l2} = Links.get_or_create(op.id, ar.id)`; `{:ok, l2} = Links.set_status(l2, "linked", %{summary: "Adopted from the lectern."})`; `Links.store_edges(l2, [%{"from" => op_n.id, "to" => ar_n.id, "type" => "echoes", "why" => "Sauer's framing."}], Linker.types())`.
8. Context returned: `%{conn: conn, owner: owner, op: op, ar: ar, di: di}`.

The conn is NOT logged in (no `log_in_user`) in this file; the `/cases` page is public. No LLM is involved.

### test "the record facts a reader checks first are on the card"
- visit `live(conn, ~p"/cases")` -> path `/cases`.
- assert html =~ "No. 25-332"
- assert html =~ "Argued December 8, 2025"
- assert html =~ "Decided June 29, 2026"
- assert html =~ "question presented"
- assert html =~ "Humphrey&#39;s Executor"   (HTML-escaped apostrophe: `Humphrey's Executor`)
- 5 assertions.

### describe "the holding"
Comment above describe: "Lawyers do not read the syllabus, and the syllabus says why: it is no part of the opinion. It was the source of "what the Court held"." The global setup still runs for each test in the describe.

#### test "the record carries no headnote any more"  (describe "the holding")
- `rec = Marginalia.Cases.Record.for("Wolford v. Lopez")` (arity 1)
- assert rec.docket == "No. 24-1046"
- refute Map.has_key?(rec, :held)   (the record map has no `:held` key)
- 2 assertions.

#### test "it is the Court's own sentence, lifted from the opinion"  (describe "the holding")
- Input body (heredoc; text has no leading indentation, ends with a trailing newline):
```
The Government says otherwise. We are not persuaded. We hold that the
statute does not reach conduct outside the United States. It is so ordered.
```
- `held = Cases.holding(%Marginalia.Works.Work{body: body})` (`Marginalia.Cases.holding/1` takes a Work struct; only `body` set)
- assert held == "We hold that the statute does not reach conduct outside the United States."   (the two source lines are joined into one sentence with a single space; sentence starts at "We hold", ends at the period before " It is so ordered.")
- assert String.contains?(String.replace(body, ~r/\s+/, " "), held)   (the quote is a verbatim substring of the whitespace-normalised body)
- 2 assertions.

#### test "'we hold that' is preferred over a bare 'accordingly'"  (describe "the holding")
- Input body (heredoc, trailing newline):
```
Accordingly, the court of appeals had jurisdiction to hear the appeal.
We conclude that the claim is preempted by the federal scheme.
```
- assert Cases.holding(%Marginalia.Works.Work{body: body}) =~ "the claim is preempted"
- 1 assertion. (Note the input actually contains "Accordingly," first and "We conclude that" second; the "We conclude that" sentence is the one returned, not the "Accordingly" one.)

#### test "a holding buried mid-sentence is quoted from where the sentence began"  (describe "the holding")
- Input body (heredoc, trailing newline):
```
The parties dispute the scope of the clause. Because we conclude that
Durnell's claim is expressly preempted, we need not reach the second question.
```
- `held = Cases.holding(%Marginalia.Works.Work{body: body})`
- assert String.starts_with?(held, "Because we conclude that")
- refute String.starts_with?(held, "we conclude")
- 2 assertions.

#### test "a division heading before the sentence is not part of the quotation"  (describe "the holding")
- `for lead <- ["III", "II A", "* * *", "1."]`, build
  `body = "Some earlier reasoning ends here.\n\n#{lead}\n\nWe hold that the statute is valid."`
  i.e. `Some earlier reasoning ends here.`, blank line, the lead line, blank line, `We hold that the statute is valid.`
- assert Cases.holding(%Marginalia.Works.Work{body: body}) == "We hold that the statute is valid."  with failure message `"leading #{inspect(lead)} survived into the quote"`.
- Executed for all four leads: "III", "II A", "* * *", "1.". 1 assertion in source (4 executions).

#### test "an opinion that never says it in one sentence gets nothing"  (describe "the holding")
- `body = "The judgment below rested on a mistaken premise about the text. " <> String.duplicate("More reasoning follows. ", 40)`
- assert Cases.holding(%Marginalia.Works.Work{body: body}) == nil
- 1 assertion.

#### test "the page quotes it, and says the syllabus is not a source"  (describe "the holding")
- visit `live(conn, ~p"/cases")`.
- assert html =~ "the Court, holding"
- assert html =~ "constitutes no part of the"
- assert html =~ "The Reporter&#39;s syllabus is excluded"
- refute html =~ "what the Court held"
- 4 assertions. (The opinion work body in setup contains "We hold that the removal power is the President's alone.", the source of the quoted holding.)

### test "the read pass's own account of the opinion is shown, and expands"
- `{:ok, view, html} = live(conn, ~p"/cases")`
- assert html =~ "on reading the opinion"
- assert html =~ "announces its destination in section one"   (from `first_impression`)
- comment "# clamped until asked"; assert html =~ "fi clamped"   (a CSS class `fi clamped` on the first-impression element)
- action: `html = view |> element("button[phx-value-slug='trump-v-slaughter']") |> render_click()` (the expand button, attribute `phx-value-slug='trump-v-slaughter'`)
- refute html =~ "fi clamped"
- 4 assertions.

### test "every document is named and carries its source"  (context `%{conn: conn, ar: ar}`)
- visit `/cases`.
- comment "# the advocate, not "Oral argument" three times over"; assert html =~ "Argument: Gen. D. John Sauer"
- assert html =~ "Opinion of the Court"
- assert html =~ "supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf"
- comment "# and each one opens the case read on that document"; assert html =~ "/cases/trump-v-slaughter/read/#{ar.slug}"   (ar.slug = slug of the argument work)
- 4 assertions.

### test "the card offers pairings, which are how a case is actually read"
- visit `/cases`.
- comment: "# one document against another, landing in the reading where the second follows the first"
- assert html =~ ~s(class="cs-ways")
- assert html =~ "against"
- assert html =~ ~r{href="/links/\d+\?lead=}
- comment "# the opinion leads the pair, not the dissent"; assert html =~ ~r{class="a opinion"[^>]*>\s*Opinion of the Court}
- comment "# the whole-case and connections views are the quiet alternatives"
- assert html =~ "or all 3 at once →"   (arrow is U+2192; 3 = number of documents in the case)
- assert html =~ "connections →"
- 6 assertions.

### test "the hook is a real disagreement, before any explanation"
- visit `/cases`.
- assert html =~ ~s(class="cs-hook")
- assert html =~ "no founding-era support"   (from the tension edge's `why`)
- comment "# the method is folded, and below"; assert html =~ ~s(<details class="cs-how")
- 3 assertions.

### test "one case is one case, not 1 cases"
- visit `/cases`.
- assert html =~ "</b> case</span>"
- refute html =~ "</b> cases</span>"
- assert html =~ "1 case from the Supreme Court"
- 3 assertions.

### test "the lede counts the cases it is actually showing"
- Comment above the test: ""Four cases from the Supreme Court's last quarter" was true of four cases and then quietly false of sixteen."
- visit `/cases`.
- refute html =~ "Four cases"
- comment "# the year comes off the decision dates of the cases on the page"; assert html =~ "2025 term"
- 2 assertions.

### test "it opens with one real connection, not a description of one"
- visit `/cases`.
- assert html =~ "for instance"
- assert html =~ "no founding-era support"
- assert html =~ "read it →"
- 3 assertions.

### test "the provenance note says what this is and is not"
- visit `/cases`.
- assert html =~ "Supreme Court of the United States"
- assert html =~ "verified against the source"
- assert html =~ "a substitute for reading the opinion"
- 3 assertions.

### test "a visitor who is not the owner sees all of it"  (context `%{}`)
- `{:ok, _view, html} = live(build_conn(), ~p"/cases")` (fresh unauthenticated conn)
- assert html =~ "The term, read closely"
- assert html =~ "No. 25-332"
- 2 assertions.

### test "a summary calls the documents by name, not Manuscript A and B"  (context `%{conn: conn, op: op, di: di}`)
- comment: "# by name, not the head of the list: `op` has two links and this asserts on which documents A and B resolve to"
- `l = Enum.find(Links.for_work(op.id), &(&1.a_work_id == di.id or &1.b_work_id == di.id))` (the opinion-dissent link)
- `{:ok, l} = Links.set_status(l, "linked", %{summary: "Manuscript A grounds removal in the Framers; Manuscript B does not."})`
- assert Links.summary(l) =~ "Opinion of the Court grounds removal"
- assert Links.summary(l) =~ "Dissent (Sotomayor) does not"
  (Names are the work titles with the "Trump v. Slaughter — " prefix stripped. A resolves to the opinion, B to the dissent, according to the link's work ordering.)
- refute Links.summary(l) =~ "Manuscript"
- then `{:ok, _view, html} = live(conn, ~p"/cases")`; refute html =~ "Manuscript A"
- 4 assertions. `Links.summary/1` takes a link struct and returns the display string.

### test "a bare A and B at the start of a sentence are named too"  (context `%{op: op, di: di}`)
- Comment above: ""A says Congress entrenched the common law; B Jackson charges that..." is a sentence a reader has to decode before they can read it."
- Comment inside: "# the dissent link by name, not the head of the list: `op` has two links and this asserts on which documents A and B resolve to"
- Same `Enum.find` for the dissent link.
- `Links.set_status(l, "linked", %{summary: "A says Congress entrenched the common law; B charges that it did not."})`
- assert Links.summary(l) =~ "Opinion of the Court says Congress entrenched"
- assert Links.summary(l) =~ "Dissent (Sotomayor) charges that it did not"
- 2 assertions.

### test "a lettered part of a statute is not a document"  (context `%{op: op}`)
- `[l | _] = Links.for_work(op.id)` (whichever link is first)
- `text = "The majority relies on Part A of the statute and Exhibit B at trial."`
- `{:ok, l} = Links.set_status(l, "linked", %{summary: text})`
- assert Links.summary(l) == text   (unchanged)
- 1 assertion.

### test "a summary that never mentioned a manuscript is left alone"  (context `%{op: op}`)
- `[l | _] = Links.for_work(op.id)`; `{:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree about removal."})`
- assert Links.summary(l) == "They disagree about removal."
- 1 assertion.

### test "a collection with no public record still renders"  (context `%{conn: conn, owner: owner}`)
- `body = "# Loose\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)`
- `{:ok, w} = Works.create_work(owner.id, %{"title" => "Loose ends", "body" => body})`; `{:ok, w} = Works.set_status(w, "read")`; `{:ok, _} = Cases.place(w, "Not a court case", "opinion")`
- visit `live(conn, ~p"/cases")` -> `/cases`
- assert html =~ "Not a court case"
- 1 assertion. (A collection with no entry in `Cases.Record` renders without crashing, showing its name.)

Behavior not obvious from the code:
- The sandbox is switched to `{:shared, self()}`, so the module is not async-safe; `:owner_email` is mutated globally and must be restored (see the quoted comment).
- The case index is public: the non-owner and unauthenticated visitor test shows everything ("The term, read closely", "No. 25-332").
- The page's holding quote is lifted from the opinion body, not from any syllabus; the page text must say "The Reporter's syllabus is excluded" and "constitutes no part of the" and must not say "what the Court held". `Cases.holding/1` rules pinned by tests: a "We hold that" sentence returns exactly that sentence (joined across the newline); a "We conclude that" sentence beats an earlier "Accordingly," sentence; if the key phrase is mid-sentence (", Because we conclude that ...") the quote starts at the sentence start; standalone division headings (`III`, `II A`, `* * *`, `1.`) preceding the sentence are not included; nil when no single sentence states a holding.
- The case count is pluralised: with one case the page says "1 case from the Supreme Court" and `</b> case</span>`, never `</b> cases</span>`. The "2025 term" label is derived from decision dates of the displayed cases (comment: "Four cases from the Supreme Court's last quarter" was true of four cases and then quietly false of sixteen.).
- `Links.summary/1` rewrites "Manuscript A"/"Manuscript B" and a sentence-initial bare "A"/"B" into document names (title minus the "Collection — " prefix), but leaves "Part A" / "Exhibit B" alone, and leaves summaries with no manuscript reference unchanged.
- Pairing links look like `/links/<id>?lead=<slug>`, opinion first (class `a opinion`).
- Element classes relied on: `cs-ways`, `cs-hook`, `cs-how` (a `<details>`), `fi clamped`.

## test/marginalia_web/live/case_page_test.exs  (8 tests; covers the public LiveView at `/cases/:slug`, here `/cases/some-v-case`)

Module `MarginaliaWeb.CasePageTest`. Aliases `Marginalia.{Cases, Links, Works}`, `Marginalia.Analysis.Linker`.

Moduledoc: "The case page: it renders, and the connections can be sliced. There was no test for this page at all, and it shipped raising BadBooleanError on every load — `@q != "" or @kind or @pair`, where a nil filter is not a boolean and `false or nil` raises."

### Shared setup
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. Same `:owner_email` put_env to "owner@example.com" with `on_exit` restore-or-delete (identical comment as in case_index_test).
3. `owner = user_fixture(%{email: "owner@example.com"})`.
4. Helper `mk = fn title, role ->`: `body = "# #{title}\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 200)`; `Works.create_work(owner.id, %{"title" => title, "body" => body})`; `Works.set_status(w, "read")`; `Cases.place(w, "Some v. Case", role)`; `s = hd(Works.list_sections(w.id))`; `Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in the #{role}", quote: "A sentence long enough"})`; returns `{w, n}`.
5. `{op, op_n} = mk.("Some v. Case — Opinion", "opinion")`; `{di, di_n} = mk.("Some v. Case — Dissent", "dissent")`.
6. `{:ok, link} = Links.get_or_create(op.id, di.id)`; `{:ok, _} = Links.set_status(link, "linked", %{summary: "They disagree."})`.
7. `Links.store_edges(link, [ %{"from" => op_n.id, "to" => di_n.id, "type" => "tension", "why" => "They part on consent."}, %{"from" => di_n.id, "to" => op_n.id, "type" => "answers", "why" => "It replies about standing."} ], Linker.types())`.
8. Returns `%{conn: conn, owner: owner, op: op}`.

Not logged in by default. No LLM involvement.

### test "it renders at all, with no filters set"
- `{:ok, _view, html} = live(conn, ~p"/cases/some-v-case")`
- assert html =~ "Some v. Case"
- assert html =~ "They part on consent."
- comment "# the clear button only appears once something is filtered"; refute html =~ ">clear<"
- 3 assertions.

### test "searching narrows the connections"
- `{:ok, view, _} = live(conn, ~p"/cases/some-v-case")`
- `html = render_change(view, "search", %{"q" => "consent"})` (event "search", params `%{"q" => "consent"}`)
- assert html =~ "They part on consent."
- refute html =~ "It replies about standing."
- assert html =~ ">clear<"
- comment "# and clearing brings them back"; `html = render_click(view, "clear", %{})` (event "clear")
- assert html =~ "It replies about standing."
- 4 assertions.

### test "slicing by relation, and toggling it off again"
- live view at `/cases/some-v-case`.
- `html = render_click(view, "kind", %{"k" => "tension"})` (event "kind", param `"k" => "tension"`)
- assert html =~ "They part on consent."
- refute html =~ "It replies about standing."
- `html = render_click(view, "kind", %{"k" => "tension"})` (same click again toggles off)
- assert html =~ "It replies about standing."
- 3 assertions.

### test "a search matching nothing says so"
- `html = render_change(view, "search", %{"q" => "zzzzz"})`
- assert html =~ "Nothing matches that"
- 1 assertion.

### test "the fast track into a referential read is on the page"  (context `%{conn: conn, op: op}`)
- visit `/cases/some-v-case`.
- assert html =~ "or one against another"
- comment "# the label is the document's own name, which here is "Opinion""; assert html =~ "Opinion ↔ Dissent"   (U+2194)
- comment "# and it leads with the opinion"; assert html =~ "lead=#{op.slug}"
- 3 assertions.

### test "each document is named by what distinguishes it"  (context `%{conn: conn, owner: owner}`)
- Comment above: "Three advocates all labelled "Oral argument" is not a label."
- `body = "# x\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 200)`
- `for who <- ["Argument: Amit Agarwal", "Argument: Gen. D. John Sauer"]`: `Works.create_work(owner.id, %{"title" => "Some v. Case — #{who}", "body" => body})`, `Works.set_status(w, "read")`, `Cases.place(w, "Some v. Case", "argument")`.
- visit `/cases/some-v-case`.
- assert html =~ "Argument: Amit Agarwal"
- assert html =~ "Argument: Gen. D. John Sauer"
- refute html =~ ">Oral argument<"
- 3 assertions.

### test "a visitor who is not the owner still sees it"  (context `%{}`)
- `{:ok, _view, html} = live(build_conn(), ~p"/cases/some-v-case")`
- assert html =~ "Some v. Case"
- 1 assertion.

### test "the way in is in the nav for everyone, signed in or not"
- comment: "# the collections are published on purpose; hiding the link behind a login hid the only public thing on the site"
- `logged_out = get(build_conn(), ~p"/cases") |> html_response(200)` (plain controller-style GET of `/cases`, status 200)
- assert logged_out =~ ~s(href="/cases")
- `signed_in = conn |> log_in_user(user_fixture()) |> get(~p"/cases") |> html_response(200)` (`log_in_user` from ConnCase; `user_fixture()` with defaults, not the owner)
- assert signed_in =~ ~s(href="/cases")
- 2 assertions.

Behavior not obvious from the code:
- Regression: the page "shipped raising BadBooleanError on every load" because of `@q != "" or @kind or @pair` with nil filters; the first test (no filters set) is the guard. The "clear" button (text `>clear<`) only exists once a filter (search text, relation kind, or pair) is set.
- "kind" click is a toggle: clicking the same `k` twice returns to unfiltered. "search" is a `phx-change`-style event (`render_change`), "clear" resets all filters.
- A search for text found only in one edge's `why` hides edges whose why does not match ("It replies about standing."); empty result shows "Nothing matches that".
- Document labels: documents in the same role (two arguments) are labelled by the title suffix after the em dash ("Argument: Amit Agarwal"), never a generic "Oral argument". For the single opinion/dissent the label is "Opinion"/"Dissent", and the fast-track link text is "Opinion ↔ Dissent" with an href containing `lead=<opinion slug>`.
- The `/cases` nav link `href="/cases"` appears on `/cases` both for anonymous and signed-in users.


# =====================================================================
# ROUTE GROUP B: /cases/:slug/read and /cases/:slug/read/:doc_slug (case read)
# =====================================================================

## test/marginalia_web/live/case_read_test.exs  (22 tests; covers LiveView `MarginaliaWeb.CaseLive.Read` at `/cases/:slug/read[/:work_slug]`, `MarginaliaWeb.CaseLive.Read.cap/1`, `Marginalia.Cases.reading/2`, `Marginalia.Cases.Chat.card/1`)

Module `MarginaliaWeb.CaseReadTest`. Aliases `Marginalia.{Cases, Links, Works}`, `Marginalia.Analysis.Linker`. `@quote "A sentence long enough"`.

Moduledoc: "Reading one document of a case with every other document in the margin. The thing worth pinning is the merge: two *separate* links, both touching the opinion, have to arrive in one margin on the same paragraph. Reading the pairs one at a time is what this page exists not to do."

### Shared setup (applies to every test, including describe blocks)
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. `:owner_email` put_env "owner@example.com", restored in `on_exit` (restore previous value, or `delete_env` if it was nil), same comment as case_index_test ("Restored, not deleted. ...").
3. `owner = user_fixture(%{email: "owner@example.com"})`.
4. Helper `mk = fn title, role ->`: `body = "# #{title}\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)`; `Works.create_work(owner.id, %{"title" => title, "body" => body})`; `Works.set_status(w, "read")`; `Cases.place(w, "Some v. Case", role)`; `s = hd(Works.list_sections(w.id))`; `Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in the #{role}", body: "what the #{role} is doing here", quote: @quote})`; returns `{w, n}`.
5. Three works: `{op, op_n} = mk.("Some v. Case — Opinion", "opinion")`; `{di, di_n} = mk.("Some v. Case — Dissent", "dissent")`; `{ar, ar_n} = mk.("Some v. Case — Argument: Counsel", "argument")`. (Em dash separator.)
6. Helper `join = fn a, a_n, b, b_n, type, why ->`: `Links.get_or_create(a.id, b.id)`; `Links.set_status(l, "linked", %{summary: "#{type} between them."})`; `Links.store_edges(l, [%{"from" => a_n.id, "to" => b_n.id, "type" => type, "why" => why}], Linker.types())`; returns link.
7. Three links:
   - `join.(op, op_n, di, di_n, "tension", "They part on consent.")`
   - `join.(op, op_n, ar, ar_n, "answers", "The lectern already settled this.")`
   - comment "# a link that does not touch the opinion at all, to prove the margin is the lead's links and not the whole collection's": `join.(di, di_n, ar, ar_n, "echoes", "Dissent and counsel agree here.")`
8. Context: `%{conn: conn, owner: owner, op: op, di: di, ar: ar}`.

Not logged in; the page is public. Default lead (when no doc slug is given) is the opinion.

### test "the opinion is read with both other documents in one margin"
- `{:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")` -> `/cases/some-v-case/read`
- assert html =~ "Reading…"   (U+2026 ellipsis)
- assert html =~ "Some v. Case — Opinion"
- comment "# both reasons, from two separate links, on the page at once": assert html =~ "They part on consent."
- assert html =~ "The lectern already settled this."
- comment "# and not the link between the other two, which the opinion is not in": refute html =~ "Dissent and counsel agree here."
- 5 assertions.

### test "each note says which document it came from, without the case name"
- visit `/cases/some-v-case/read`.
- assert html =~ ~s(<span class="src">Dissent</span>)
- assert html =~ ~s(<span class="src">Argument: Counsel</span>)
- 2 assertions. (Source label is the title with the case name prefix "Some v. Case — " stripped.)

### test "the far passage travels with the note"
- visit `/cases/some-v-case/read`.
- assert html =~ "<blockquote>#{@quote}</blockquote>"   i.e. `<blockquote>A sentence long enough</blockquote>`
- 1 assertion.

### test "a source chip narrows the margin to one document"  (context `%{conn: conn, di: di}`)
- `{:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")`
- `html = view |> element("button[phx-value-w='#{di.id}']") |> render_click()` (chip button with `phx-value-w` = dissent work id)
- assert html =~ "They part on consent."
- refute html =~ "The lectern already settled this."
- `html = view |> element("button.cr-clear") |> render_click()` (clear button, class `cr-clear`)
- assert html =~ "The lectern already settled this."
- 3 assertions.

### test "a relation chip narrows the margin to one kind"
- live view at `/cases/some-v-case/read`.
- `html = view |> element("button[phx-value-k='answers']") |> render_click()`
- assert html =~ "The lectern already settled this."
- refute html =~ "They part on consent."
- 2 assertions.

### test "any document in the case can be the one you read"  (context `%{conn: conn, ar: ar}`)
- `{:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read/#{ar.slug}")` -> `/cases/some-v-case/read/<argument work slug>`
- assert html =~ "Some v. Case — Argument: Counsel"
- comment "# from the argument's side it sees both of its own links": assert html =~ "The lectern already settled this."
- assert html =~ "Dissent and counsel agree here."
- refute html =~ "They part on consent."
- 4 assertions.

### test "the case page offers the whole-case read before the pairs"
- `{:ok, _view, html} = live(conn, ~p"/cases/some-v-case")` (the case page, `/cases/some-v-case`)
- assert html =~ ~p"/cases/some-v-case/read"   (i.e. the string `/cases/some-v-case/read` appears)
- assert html =~ "with 2 other documents in the margin"
- 2 assertions.

### describe "a case related to another case"
Additional `setup %{owner: owner, op: op}` (runs after the global setup):
- `body = "# other\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)`
- `far`: `Works.create_work(owner.id, %{"title" => "Other v. Matter — Opinion", "body" => body})`; `Works.set_status(far, "read")`; `Cases.place(far, "Other v. Matter", "opinion")` (a second collection, slug presumably `other-v-matter`)
- `s = hd(Works.list_sections(far.id))`; `far_n` = `Works.insert_node(%{work_id: far.id, section_id: s.id, node_type: "beat", title: "a beat in the other case", quote: @quote})`
- `[op_n] = Works.list_nodes(op.id) |> Enum.filter(&(&1.node_type == "beat")) |> Enum.take(1)` (the opinion's beat node)
- `{:ok, l} = Links.get_or_create(op.id, far.id)`; `Links.set_status(l, "linked", %{summary: "Two cases, one question."})`; `Links.store_edges(l, [%{"from" => op_n.id, "to" => far_n.id, "type" => "echoes", "why" => "The same Court on the same clause, three weeks apart."}], Linker.types())`
- returns `%{far: far}`.

#### test "its notes appear in the margin, saying where they are from"  (describe "a case related to another case")
- visit `/cases/some-v-case/read`.
- assert html =~ "The same Court on the same clause"
- assert html =~ ~s(<p class="from">Other v. Matter</p>)
- comment "# and it is visibly not from this case": assert html =~ "cr-note s0 far"
- 3 assertions.

#### test "the chip for another case names the case, not the document"  (describe "a case related to another case")
- visit `/cases/some-v-case/read`.
- assert html =~ ~r{cr-chip[^"]*far[^>]*>\s*<span class="t">Other v. Matter}
- 1 assertion.

#### test "a connection from another case is marked as such in the context"  (describe "a case related to another case"; context `%{}`)
- `c = Cases.published() |> Enum.find(&(&1.name == "Some v. Case"))`
- `reading = Cases.reading(c, Cases.default_lead(c).id)` (`Cases.reading/2`: case, lead work id)
- assert Marginalia.Cases.Chat.card(reading) =~ "a different case"
- 1 assertion. (`Marginalia.Cases.Chat.card/1` builds the chat's context text.)

#### test "filtering to this case's own documents leaves it out"  (describe "a case related to another case")
- visit `/cases/some-v-case/read`; click `button[phx-value-w='#{di.id}']` (dissent chip).
- refute html =~ "The same Court on the same clause"
- 1 assertion.

### describe "the phone's margin"
Comment above describe: "On a phone the margin cannot be a column of cards — two columns of prose at 390px is twenty-four characters a line. It becomes a rail of marks beside the text, and a tap brings the notes up in a sheet."

Private helper in the module:
```elixir
defp first_ref(view) do
  [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, render(view))
  ref
end
```
(the first `phx-value-ref` attribute value found in the rendered view.)

#### test "every linked paragraph carries a rail with its relations on it"
- visit `/cases/some-v-case/read`.
- assert html =~ ~s(class="cr-rail")
- assert html =~ ~s(<span class="tick k-tension">)
- assert html =~ ~s(<span class="tick k-answers">)
- assert html =~ "connections on this paragraph"
- 4 assertions.

#### test "tapping the rail opens that paragraph's notes, and closing dismisses them"
- `html = view |> element("button.cr-rail") |> render_click()` (this requires exactly one `button.cr-rail` in the page, i.e. one linked paragraph)
- assert html =~ ~s(class="cr-sheet")
- assert html =~ "on this paragraph"
- assert html =~ "They part on consent."
- refute render_click(view, "unpeek", %{}) =~ ~s(class="cr-sheet")   (event "unpeek" closes the sheet)
- 4 assertions.

#### test "a filter change dismisses a sheet that may no longer apply"  (context `%{conn: conn, di: di}`)
- click `button[phx-value-w='#{di.id}']` (filter to dissent)
- assert render_click(view, "peek", %{"ref" => first_ref(view)}) =~ ~s(class="cr-sheet")   (event "peek" with the first `phx-value-ref` value)
- comment "# clearing the filter changes what the rail would show, so the sheet standing open over it would be showing the wrong paragraph's notes"
- refute view |> element("button.cr-clear") |> render_click() =~ ~s(class="cr-sheet")
- 2 assertions.

### describe "the chat about the case"

#### test "the bubble is there and opens a panel about the case"
- `{:ok, view, html} = live(conn, ~p"/cases/some-v-case/read")`
- assert html =~ "lc-bubble"
- refute html =~ "lc-panel"
- `html = view |> element("button.lc-bubble") |> render_click()`
- assert html =~ "lc-panel"
- comment "# it holds a case, not a pair, and says so": assert html =~ "About this case"
- refute html =~ "About this pair"
- assert html =~ ~s(phx-submit="chat_send")
- 6 assertions.

#### test "a note carries its connection into the chat"  (context `%{conn: conn, op: op}`)
- `{:ok, view, html} = live(conn, ~p"/cases/some-v-case/read")`
- assert html =~ ~s(phx-click="cite_edge")
- comment "# one such button per note, so name the connection": `[edge | _] = Links.edges(hd(Links.for_work(op.id)))`
- `html = view |> element("button[phx-value-edge='#{edge.id}']") |> render_click()`
- comment "# citing opens the panel with that connection in it": assert html =~ "lc-panel"
- assert html =~ "lc-cited" or html =~ "tension"   (a single assertion with `or`)
- 3 assertions.

#### test "asking keeps the question and does not hang"  (LLM failure path)
- visit `/cases/some-v-case/read`; `view |> element("button.lc-bubble") |> render_click()` to open the panel.
- `view |> form("form[phx-submit=chat_send]", %{"message" => "Who conceded what?"}) |> render_submit()`
- `html = render_async(view, 5_000)` (waits up to 5000 ms for the `start_async(:chat, ...)` task)
- assert html =~ "Who conceded what?"
- refute html =~ "lc-thinking"
- 2 assertions. LLM mechanism: none stubbed. `CaseChat.ask/3` runs in `start_async` and, with test config (API keys nil, endpoints refuse), returns an error or exits; the LiveView then sets `chat_thinking: false` and puts the flash `"That did not go through: <inspect reason>"` while keeping the user's message in `chat_history`. The test only requires the question text to remain rendered and the thinking indicator (`lc-thinking`) to be gone; it does not assert on the flash.

#### test "the context names documents rather than lettering them"  (context `%{}`)
- `c = Cases.published() |> hd()`; `reading = Cases.reading(c, Cases.default_lead(c).id)`; `card = Marginalia.Cases.Chat.card(reading)`
- assert card =~ "Dissent"
- assert card =~ "Argument: Counsel"
- comment "# the pairwise chat labels its two documents A and B and the answers came back full of "A:[4030]"; with four documents that is useless"
- refute card =~ ~r/\bA:\[\d+\]/
- refute card =~ ~r/^A: /m
- 4 assertions.

### describe "a hub paragraph"
Comment (inside the first test): "Taking the first five in source order would show five from the dissent and none from either advocate on exactly the paragraphs where all three have something to say."

Pure function `MarginaliaWeb.CaseLive.Read.cap/1` (arity 1): takes a list of note maps (each with `:from_work`), returns `{shown, rest}`. The module cap constant is 5 (`@cap 5`): lists of length <= 5 return `{notes, []}`; otherwise notes are grouped by `from_work` (groups ordered by first appearance), interleaved round-robin, and split at 5.

#### test "the visible notes are spread across the documents, not taken in order"
- Input: `notes = List.duplicate(%{from_work: 1}, 6) ++ List.duplicate(%{from_work: 2}, 4) ++ List.duplicate(%{from_work: 3}, 2)` (12 notes: six of work 1, four of work 2, two of work 3, in that order)
- `{shown, rest} = MarginaliaWeb.CaseLive.Read.cap(notes)`
- assert length(shown) == 5
- assert length(rest) == 7
- assert shown |> Enum.map(& &1.from_work) |> Enum.uniq() |> length() == 3   (all three documents represented among the 5 shown)
- 3 assertions.

#### test "a short stack is not folded at all"
- `notes = List.duplicate(%{from_work: 1}, 5)`
- assert {^notes, []} = MarginaliaWeb.CaseLive.Read.cap(notes)   (pattern match: same list returned unchanged, empty rest)
- 1 assertion.

#### test "nothing is lost to the cap"
- `notes = for i <- 1..18, do: %{from_work: rem(i, 3), n: i}` (18 notes cycling from_work 1,2,0,1,2,0,...)
- `{shown, rest} = cap(notes)`
- assert Enum.sort_by(shown ++ rest, & &1.n) == notes
- 1 assertion.

### test "an unknown case sends you back to the list"  (top level, last test)
- assert {:error, {:live_redirect, %{to: "/cases"}}} = live(conn, ~p"/cases/nope/read")
- 1 assertion.

Behavior not obvious from the code:
- The point of the page: notes from two separate links that both touch the opinion are merged into one margin on the same paragraph; links not touching the lead document (dissent-argument) are excluded when reading from the opinion, but when reading from the argument both of the argument's links appear and the opinion-dissent one does not.
- Notes labelled by source document with case-name prefix stripped; notes from a different case ("Other v. Matter") carry class `cr-note s0 far`, a `<p class="from">Other v. Matter</p>` line, and their chip names the case (not the document). In the chat context card the far connection is marked "a different case". Filtering to a document of this case (`phx-value-w`) drops far-case notes.
- `phx-value-w` = work id (chip filter), `phx-value-k` = relation kind, `phx-value-ref` = paragraph ref (peek), `phx-value-edge` = edge id (cite_edge). `button.cr-clear` clears filters; filter change also closes any open peek sheet (the comment explains why).
- Chat: bubble `button.lc-bubble` toggles panel `lc-panel`; "About this case" not "About this pair"; form `phx-submit="chat_send"` with field `message`. The pairwise-chat letter labels ("A:[4030]") must not appear in the case card; documents are named ("Dissent", "Argument: Counsel").
- Unknown case on `/cases/:slug/read` is a `live_redirect` to `/cases` (not a 404).
- Relevant source behaviour verified in lib: `chat_send` ignores empty/whitespace text or when a request is in flight; on error it clears `chat_thinking` and flashes `"That did not go through: ..."`.

# =====================================================================
# ROUTE GROUP C: guided tour across /cases, /links/:id/read and /cases/:slug/read/:doc_slug
# =====================================================================

## test/marginalia_web/live/cases_tour_test.exs  (12 tests; covers `Marginalia.Walkthrough.Cases` (steps/1, for_view?/1) and the tour overlay/hand-over on `/cases`, `/links/:id/read?lead=..&walk=1`, `/cases/:slug/read/:doc?walk=1`)

Module `MarginaliaWeb.CasesTourTest`. Aliases `Marginalia.{Cases, Links, Works}`, `Marginalia.Analysis.Linker`, `Marginalia.Walkthrough`. `@quote "A sentence long enough"`.

Moduledoc: "The guided run through a term. What is worth pinning is not the copy, it is the two things that make it a tour rather than three unrelated overlays: every step points at something that is actually on its page, and each leg hands over to the next."

### Shared setup (applies to all tests, including describes)
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. `:owner_email` put_env "owner@example.com", `on_exit` restores previous value or deletes if it was nil (same "Restored, not deleted." comment as case_index_test).
3. `owner = user_fixture(%{email: "owner@example.com"})`.
4. Helper `mk = fn title, role ->`: `body = "# #{title}\n\n#{@quote} to be a section. We hold that it is so.\n\n" <> String.duplicate("word ", 200)`; `Works.create_work(owner.id, %{"title" => title, "body" => body})`; `Works.set_status(w, "read")`; `Cases.place(w, "Some v. Case", role)`; first section `s`; `Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat", title: "a beat in the #{role}", quote: @quote})`; returns `{w, n}`.
5. `{op, op_n} = mk.("Some v. Case — Opinion of the Court", "opinion")`; `{di, di_n} = mk.("Some v. Case — Dissent (Jackson)", "dissent")`.
6. `{:ok, l} = Links.get_or_create(op.id, di.id)`; `Links.set_status(l, "linked", %{summary: "They disagree."})`; `Links.store_edges(l, [%{"from" => op_n.id, "to" => di_n.id, "type" => "tension", "why" => "They part."}], Linker.types())`.
7. Context: `%{conn: conn, owner: owner, op: op, di: di, link: l}`.

conn is not logged in for any test in this file. No LLM calls.

### describe "the steps themselves"  (pure functions; no DB use beyond the shared setup)

#### test "every leg has steps, and every step says something"
- `for leg <- [:cases, :follow, :case_read]`: `steps = Walkthrough.Cases.steps(leg)` (`Marginalia.Walkthrough.Cases.steps/1`, arg is a leg atom, returns list of step maps).
  - assert length(steps) >= 5, "#{leg} is too short to be a tour"
  - for each step `s`:
    - assert s.title != ""
    - assert String.length(s.body) > 40, "#{leg}/#{s.id} says nothing"
    - assert Map.has_key?(s, :target)
- Step maps therefore have keys `:id`, `:title`, `:body` (> 40 chars) and `:target` (key must exist; value not checked). 4 assertions in source.

#### test "a view with no leg gets none"
- assert Walkthrough.Cases.steps(:graph) == []
- refute Walkthrough.Cases.for_view?(:graph)   (`for_view?/1` arity 1)
- 2 assertions.

#### test "each leg but the last hands over to the next"
- assert %{act: %{kind: "hop", to: "first_pair"}} = List.last(Walkthrough.Cases.steps(:cases))   (the last step of leg `:cases` has `act: %{kind: "hop", to: "first_pair"}`)
- assert %{act: %{kind: "hop", to: "case_read"}} = List.last(Walkthrough.Cases.steps(:follow))
- refute Map.has_key?(List.last(Walkthrough.Cases.steps(:case_read)), :act)   (the last leg's last step has no `:act` key)
- 3 assertions.

### describe "running it"

Comment above the first test: "The overlay always ships with the page and the browser decides whether to run it, against a flag in localStorage. That is what lets this page work with no account: "has this person seen the tour" is a fact about a browser, and making it a fact about a user is why there were 762 accounts."

#### test "the page always carries the tour, and says to gate it locally"
- `{:ok, _view, html} = live(conn, ~p"/cases")` -> `/cases`
- assert html =~ ~s(id="walk")
- assert html =~ ~s(data-auto="cases")
- assert html =~ "One real disagreement, first"
- assert html =~ "Take the tour"
- 4 assertions.

#### test "no account is created to remember it"
- `before = Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count)`
- `live(conn, ~p"/cases")` twice: once with the context conn, once with `build_conn()`.
- assert Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count) == before, "a read-only public page minted an account"
- 1 assertion.

#### test "a signed-out visitor is not told they are a guest"
- visit `/cases`.
- assert html =~ "Log in"
- refute html =~ ">guest<"
- 2 assertions.

#### test "the button asks the overlay directly, with no round trip"
- visit `/cases`.
- assert html =~ "mg:walk"   (a client-side event name `mg:walk`)
- comment "# there is no server event left to start or end it": refute html =~ ~s(phx-click="start_walk"); refute html =~ ~s(phx-click="end_walk")
- 3 assertions.

#### test "arriving with walk=1 starts the pairwise leg, instead of the one-time card"  (context `%{conn: conn, link: l, op: op}`)
- `{:ok, _view, html} = live(conn, ~p"/links/#{l.id}/read?lead=#{op.slug}&walk=1")` -> `/links/<link id>/read?lead=<opinion slug>&walk=1`
- assert html =~ "Left is read. Right is the reference"
- comment "# the tour card would be a second overlay over the first": refute html =~ "Two documents, read as one"
- 2 assertions.

#### test "the pairwise leg hands over to the whole-case reading"  (context `%{conn: conn, link: l, op: op}`)
- `{:ok, view, _html} = live(conn, ~p"/links/#{l.id}/read?lead=#{op.slug}&walk=1")`
- assert {:error, {:live_redirect, %{to: to}}} = render_click(view, "walk_hop", %{"to" => "case_read"})   (event "walk_hop" with param `"to" => "case_read"`)
- assert to == "/cases/some-v-case/read/#{op.slug}?walk=1"
- 2 assertions.

#### test "the last leg runs on the whole-case reading and ends there"  (context `%{conn: conn, op: op}`)
- `{:ok, view, html} = live(conn, ~p"/cases/some-v-case/read/#{op.slug}?walk=1")`
- assert html =~ "The whole case in one margin"
- refute render_click(view, "end_walk", %{}) =~ ~s(id="walk")   (event "end_walk" removes the overlay element `id="walk"`)
- 2 assertions.

#### test "a brand new visitor gets it without doing anything"
- Comment above: "the whole point of the auto-run: a visitor who has never been here"
- visit `/cases` with conn: assert html =~ "One real disagreement, first"
- comment "# and a different new visitor gets it too — it is per person, not per site": `live(build_conn(), ~p"/cases")`: assert html =~ "One real disagreement, first"
- 2 assertions.

#### test "a plain visit runs no tour"  (context `%{conn: conn, op: op}`)
- `{:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read/#{op.slug}")` (no `walk` param)
- refute html =~ ~s(id="walk")
- 1 assertion.

Behavior not obvious from the code:
- The tour overlay (`id="walk"`, `data-auto="cases"`) is always rendered on `/cases` for everyone; whether it runs is decided in the browser from a localStorage flag. No server-side "seen" state and no account minted ("is why there were 762 accounts"): the user count must be unchanged after visiting `/cases` anonymously.
- The "Take the tour" button fires a client event `mg:walk`; the old server events `start_walk`/`end_walk` must not be wired as `phx-click` on `/cases`. On the read pages the `end_walk` LiveView event still exists and removes `id="walk"`.
- Tour legs: `:cases` (ends with hop to `first_pair`), `:follow` (pairwise `/links/:id/read`, ends with hop to `case_read`), `:case_read` (last leg, no `:act`). `walk=1` in the URL starts the leg. The pairwise read with `walk=1` shows the tour copy "Left is read. Right is the reference" and suppresses the one-time card "Two documents, read as one". `walk_hop` with `to: "case_read"` live-redirects to `/cases/<case slug>/read/<lead slug>?walk=1`.
- Page copy checked: "One real disagreement, first", "Take the tour", "Log in" (no ">guest<" for a signed-out visitor), "The whole case in one margin".

# =====================================================================
# ROUTE GROUP D: /links (cluster constellation)
# =====================================================================

## test/marginalia_web/live/cluster_view_test.exs  (4 tests; covers the `/links` LiveView constellation of related drafts)

Module `MarginaliaWeb.ClusterViewTest`. Moduledoc: "The constellation drawn for a group of related drafts." Aliases `Marginalia.{Links, Works}`.

### Shared setup
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. `user = user_fixture()` (default attrs).
3. Helper `make = fn title ->`: `body = "# #{title}\n\nA sentence long enough for a section.\n\n" <> String.duplicate("word ", 200)`; `Works.create_work(user.id, %{"title" => title, "body" => body})`; `Works.set_status(w, "read")`; returns w.
4. `a = make.("Miller v. Alabama — Opinion of the Court")`, `b = make.("Miller v. Alabama — Oral Argument")`, `c = make.("Miller v. Alabama — Concurrence and Dissents")` (em dashes).
5. `{:ok, l1} = Links.get_or_create(a.id, b.id)`; `Links.set_status(l1, "linked", %{summary: "The argument that produced it."})`; `{:ok, l2} = Links.get_or_create(a.id, c.id)`; `Links.set_status(l2, "linked", %{summary: "The writings that answer it."})`. (No link between b and c.)
6. Context: `%{conn: log_in_user(conn, user), a: a, b: b, c: c}` (conn logged in as that user).

Private helper in the module: `defp count(html, needle), do: length(String.split(html, needle)) - 1` (number of non-overlapping occurrences of the substring).

### test "three drafts and two links draw as one shape"
- `{:ok, _view, html} = live(conn, ~p"/links")` -> `/links`
- assert html =~ "lx-web"
- assert count(html, ~s(class="node")) == 3
- assert count(html, ~s(class="edge")) == 2
- comment "# the pair nobody has related yet, as a dashed line and in words": assert count(html, ~s(class="gap")) == 1
- assert html =~ "Not related yet:"
- 5 assertions.

### test "a node opens its draft and an edge opens that pair"  (context `%{conn: conn, a: a}`)
- visit `/links`.
- assert html =~ ~s(href="/works/#{a.slug}")
- assert html =~ ~r{href="/links/\d+"}
- 2 assertions.

### test "a lone pair is not drawn — there is no shape to show"  (context `%{conn: _conn}`)
- `Marginalia.Repo.delete_all(Marginalia.Links.Link)` (removes the setup's links)
- `user = user_fixture()` (a new user); helper `mk = fn t ->` creates a work `Works.create_work(user.id, %{"title" => t, "body" => String.duplicate("word ", 300)})` then `Works.set_status(w, "read")`.
- `{:ok, _} = Links.get_or_create(mk.("Solo one").id, mk.("Solo two").id)` (one unlinked pair)
- `{:ok, _view, html} = live(log_in_user(build_conn(), user), ~p"/links")`
- refute html =~ "lx-web"
- 1 assertion.

### @tag :screenshot  test "save the rendered page so it can be looked at"
- Not excluded by `test_helper.exs` (which only excludes `:network`), so it runs by default.
- `{:ok, _view, html} = live(conn, ~p"/links")`
- `css = File.read!("priv/static/assets/css/app.css")` (relative to the working directory; raises if the file is missing. In this worktree `priv/static/assets/css/` does not exist unless assets have been built.)
- `File.write!("/tmp/cluster.html", "<!doctype html><meta charset=utf-8><style>#{css}</style><body style='padding:2rem'>" <> Regex.replace(~r/^.*?<main[^>]*>/s, html, ""))`  (writes the page minus everything up to and including the opening `<main ...>` tag, with the CSS inlined)
- No assert/refute (0 assertions). Purely a side-effect test; the only checks are that the page renders and the file read/write do not raise.

Behavior not obvious from the code:
- A "shape" requires more than one link: 3 drafts + 2 links render markup with `class="node"` x3, `class="edge"` x2, and the unrelated pair (argument vs concurrence/dissents) as one `class="gap"` element plus the words "Not related yet:". The wrapper has class `lx-web`.
- With only a single pair there is no constellation: `lx-web` must be absent.
- Node links go to `/works/<slug>`; edge links go to `/links/<id>`.
- The screenshot-tagged test is a debugging aid that writes `/tmp/cluster.html`; to reproduce byte for byte you only need the page to render and `priv/static/assets/css/app.css` to exist.

# =====================================================================
# ROUTE GROUP E: /works/:slug  (owner's work page: changes tab, read view, confirm gate, chat drawer)
# =====================================================================

## test/marginalia_web/live/changes_tab_test.exs  (7 tests; covers `/works/:slug?view=read` and `/works/:slug?view=changes`, plus `Works.replace_block/4`)

Module `MarginaliaWeb.ChangesTabTest`. Moduledoc: "The draft as it arrived, beside the draft as it is." Alias `Marginalia.Works`.

### Shared setup
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. `user = user_fixture()` (default attrs).
3. Body (concatenated): `"# A draft\n\nALPHA the first paragraph. " <> String.duplicate("word ", 120) <> "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)`. That is one `# A draft` heading and two paragraphs starting "ALPHA the first paragraph. " and "BRAVO the second paragraph. ", each followed by "word " x120.
4. `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `{:ok, work} = Works.set_status(work, "read")`.
5. Context `%{conn: log_in_user(conn, user), work: work, user: user}` (owner, logged in).

Private helper:
```elixir
defp edit(work, from, to) do
  section = hd(Works.list_sections(work.id))

  block =
    section.body
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.find(&String.contains?(&1, from))

  {:ok, _} =
    Works.replace_block(section, block, String.replace(block, from, to),
      origin: "rewrite",
      note: "cuts the gloss"
    )
end
```
(`Works.replace_block/4`: section, old block text, new block text, opts `origin:`, `note:`.) The block is the paragraph (split on 2+ newlines) containing `from`.

### test "the tab is not offered on a draft nobody has changed"
- `live(conn, ~p"/works/#{work.slug}?view=read")` -> `/works/<slug>?view=read`
- refute html =~ ">Changes<"
- 1 assertion.

### test "it appears once there is something to show"
- `edit(work, "ALPHA", "AMENDED")`, then visit `/works/<slug>?view=read`.
- assert html =~ ">Changes<"
- 1 assertion.

### test "the old and the new are both on the page"
- `edit(work, "ALPHA", "AMENDED")`; visit `/works/<slug>?view=changes`.
- assert html =~ "As it arrived"
- assert html =~ "ALPHA", "the version that was replaced has to still be visible"
- assert html =~ "AMENDED"
- assert html =~ "1 edited"
- 4 assertions.

### test "the revision log names where each change came from"
- `edit(work, "BRAVO", "BETTER")`; visit `/works/<slug>?view=changes`.
- assert html =~ "rewrite"   (origin)
- assert html =~ "cuts the gloss"   (note)
- assert html =~ "Every change, newest first"
- 3 assertions.

### test "an untouched draft asked for the tab directly says so rather than erroring"
- visit `/works/<slug>?view=changes` without any edit.
- assert html =~ "Nothing has changed yet"
- 1 assertion.

### test "a stale summary shows the split diff under it, red out and green in"
- `section = hd(Works.list_sections(work.id))`
- Set summary fields directly:
  `{:ok, section} = section |> Ecto.Changeset.change(summary: "It sets up alpha.", summary_fingerprint: Marginalia.Summary.fingerprint(section), summary_body: section.body) |> Marginalia.Repo.update()` (fingerprint is `Marginalia.Summary.fingerprint/1` of the section at that time; `summary_body` stores the body the summary was written from)
- `block` = the paragraph of `section.body` (split on `~r/\n{2,}/`, trim) containing "ALPHA"
- `{:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))` (no origin/note opts)
- visit `/works/<slug>?view=read`.
- assert html =~ "the section has been edited since this was written"
- assert html =~ "When it was summarised"
- assert html =~ "mg-diff-cols compact"
- assert html =~ ~s(class="w del"), "the removed words carry the struck-red class"
- assert html =~ ~s(class="w ins"), "the added words carry the green class"
- 5 assertions.

### test "a current summary shows no diff at all"
- Same changeset update setting `summary: "It sets up alpha."`, `summary_fingerprint: Marginalia.Summary.fingerprint(section)`, `summary_body: section.body`; no edit.
- visit `/works/<slug>?view=read`.
- assert html =~ "It sets up alpha."
- refute html =~ "When it was summarised"
- 2 assertions.

Behavior not obvious from the code:
- The "Changes" tab (text `>Changes<`) appears only when at least one revision exists. Direct navigation to `?view=changes` on an untouched draft renders "Nothing has changed yet" instead of erroring.
- The changes view shows "As it arrived" with the replaced text still visible, a summary count "1 edited", and a revision log headed "Every change, newest first" listing each revision's origin ("rewrite") and note ("cuts the gloss").
- Summary staleness: a section summary whose `summary_fingerprint` no longer matches (after `replace_block`) shows "the section has been edited since this was written" and a diff block "When it was summarised" with container class `mg-diff-cols compact`; words removed are `<span class="w del">`, added `<span class="w ins">`. A summary whose fingerprint still matches shows only the summary text.
- LLM: none; summaries are set directly with `Ecto.Changeset.change`.

## test/marginalia_web/live/confirm_gate_test.exs  (6 tests; covers the pre-read confirm gate on `/works/:slug` for a freshly created, unread work)

Module `MarginaliaWeb.ConfirmGateTest`. Moduledoc: "The page a draft lands on before anything has been read. A stranger uploaded thirty thousand words and it sat unread for two days. The read is a button they have to press, and the button was under the section list — twenty-five rows of it, which is about eight hundred pixels, which is under the fold. The one draft nobody ran was the one with the most sections, which is exactly what pushed the button down."

### Shared setup
`setup %{conn: conn}`:
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. Comment: "the gate only offers the read when a key is configured; without one it correctly says so instead, which is a different test". `previous = Application.get_env(:marginalia, :deepseek_api_key)`; `Application.put_env(:marginalia, :deepseek_api_key, "test-key")`; `on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)` (note: restores via put_env, so a nil previous becomes an explicit nil value). This is the LLM seam: the API key is set to the dummy string "test-key"; the LLM endpoints in test config refuse connections, so any read that actually starts fails fast.
3. `user = user_fixture()`.
4. Helper `make = fn sections ->`: `body = Enum.map_join(1..sections, "\n\n", fn i -> "# Part #{i}\n\n" <> String.duplicate("word ", 300) end)`; `Works.create_work(user.id, %{"title" => "A long draft", "body" => body})`; returns w. The work is NOT set to "read" status (it stays at its initial status, awaiting confirmation).
5. Context `%{conn: log_in_user(conn, user), make: make}`.

Private helper:
```elixir
defp gate(html) do
  [_, inner] = Regex.run(~r/Before it reads(.*?)(?:<\/div>\s*<\/div>|\z)/s, html)
  inner
end
```
(captures the HTML after the text "Before it reads" up to the first `</div>` + whitespace + `</div>` or end of string.)

### test "the read can be started before the list of sections"
- `w = make.(25)`; `{:ok, _view, html} = live(conn, ~p"/works/#{w.slug}")` -> `/works/<slug>`
- assert html =~ "Read it — 25 sections"   (em dash)
- `inner = gate(html)`; `button = :binary.match(inner, "Read it —") |> elem(0)`; `list = :binary.match(inner, ~s(class="mg-rows)) |> elem(0)` (byte offsets of the first occurrences)
- assert button < list, "the only way to start a read is underneath twenty-five rows of section list"
- 2 assertions.

### test "a long draft offers it at the bottom too"
- `w = make.(25)`; visit `/works/<slug>`.
- assert length(Regex.scan(~r/Read it — 25 sections/, html)) == 2   (the button appears exactly twice)
- 1 assertion.

### test "a short draft does not repeat itself"
- `w = make.(3)`; visit `/works/<slug>`.
- assert length(Regex.scan(~r/Read it — 3 sections/, html)) == 1
- 1 assertion.

### test "pressing it starts the read"
- `w = make.(3)`; `{:ok, view, _html} = live(conn, ~p"/works/#{w.slug}")`
- `html = view |> element("button", "Read it — 3 sections") |> render_click()` (button element whose text matches "Read it — 3 sections"; there must be exactly one such button for a 3-section draft)
- assert html =~ "Reading your draft"
- assert Marginalia.Repo.reload!(w).status in ["reading", "failed", "read"]
- 2 assertions. LLM: no stub; the read starts in the background, and with the refusing endpoint it may land at "failed", hence the accepted set of statuses.

### test "with no key it says so rather than offering a button"
- `Application.put_env(:marginalia, :deepseek_api_key, nil)`; `w = make.(4)`; visit `/works/<slug>`.
- refute html =~ "Read it —"
- assert html =~ "key is configured on this deploy"
- 2 assertions.

### test "someone else's draft offers no button at all"  (context `%{make: make}`)
- `w = make.(4)` (owned by the logged-in-in-setup user, but the conn here is `build_conn()`, anonymous)
- `{:ok, _view, html} = live(build_conn(), ~p"/works/#{w.slug}")`
- refute html =~ "Read it —"
- 1 assertion.

Behavior not obvious from the code:
- The "Read it — N sections" button comes before the section list (`class="mg-rows`) in the gate markup; for long drafts (25 sections) it also repeats at the bottom (2 occurrences), for short drafts (3) it appears once. The threshold between 3 and 25 is not pinned.
- The gate (heading text "Before it reads") shows the button only when `:deepseek_api_key` is configured and the viewer is the owner; with a nil key it shows a message containing "key is configured on this deploy"; for non-owners (anonymous) there is no button.
- Regression story from the moduledoc: the button was below the fold under 25 section rows.

## test/marginalia_web/live/drawer_test.exs  (10 tests; covers the chat drawer on `/works/:slug?chat=1` and `Marginalia.Chat` functions)

Module `MarginaliaWeb.DrawerTest`. Moduledoc: "The chat as a drawer: many threads, and passages pulled out of the page and carried into the next question." Comment: "not async: the composer only renders when a key is configured, and that is global config". Aliases `Marginalia.{Chat, Works}`.

### Shared setup
`setup %{conn: conn}`:
1. `previous = Application.get_env(:marginalia, :deepseek_api_key)`; `Application.put_env(:marginalia, :deepseek_api_key, "test-key")`; `on_exit` puts `previous` back with put_env. (No Sandbox.mode call in this file: the sandbox is whatever ConnCase sets up.)
2. `user = user_fixture()`.
3. Body: `"# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\n" <> "The kettle went cold on the counter, and nobody moved to fill it again.\n\n" <> String.duplicate("word ", 260)`.
4. `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `{:ok, work} = Works.set_status(work, "read")`.
5. Context `%{conn: log_in_user(conn, user), work: work, user: user}`.

No LLM request is made in any test (no `chat_send`); the key is only to make the composer render.

### describe "many threads"

#### test "a new thread starts empty and becomes the one you are in"
- `{:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")` -> `/works/<slug>?chat=1`
- `{:ok, first} = Chat.get_or_create_conversation(work.id)` (`Marginalia.Chat.get_or_create_conversation/1`); `Chat.append(first.id, "user", "the first question I asked")` (`Chat.append/3`: conversation id, role, content)
- `html = render_click(view, "new_chat", %{})`
- comment "# the transcript is empty, but the old thread is still on the strip, named after the question that started it"
- assert html =~ ~s(class="mg-thread on")
- assert html =~ "the first question I asked"
- assert html =~ "What is actually on the page"
- assert length(Chat.list_conversations(work.id)) == 2
- 4 assertions.

#### test "switching back brings its history with it"
- `{:ok, a} = Chat.get_or_create_conversation(work.id)`; `Chat.append(a.id, "user", "about the kettle")`; `Chat.append(a.id, "assistant", "the kettle is doing a lot of work")` (before the view is mounted)
- `{:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")`; `render_click(view, "new_chat", %{})`
- comment "# gone from the transcript; the strip still lists the thread it is in": refute render(view) =~ "the kettle is doing a lot of work"
- `html = render_click(view, "switch_chat", %{"id" => a.id})`
- assert html =~ "the kettle is doing a lot of work"
- 2 assertions.

#### test "a thread is named after the question that started it"  (context `%{work: work}`; no LiveView)
- `{:ok, a} = Chat.get_or_create_conversation(work.id)`; `Chat.append(a.id, "user", "why does the prologue exist")`
- assert [%{title: "why does the prologue exist", messages: 1}] = Chat.conversation_summaries(work.id)   (`Chat.conversation_summaries/1` returns a list of maps with at least `:title` and `:messages` (count); exactly one element)
- 1 assertion.

#### test "deleting the thread you are in lands you in another"
- `{:ok, a} = Chat.get_or_create_conversation(work.id)`; mount `/works/<slug>?chat=1`; `render_click(view, "new_chat", %{})`
- assert length(Chat.list_conversations(work.id)) == 2
- `[newest | _] = Chat.list_conversations(work.id)` (list is ordered newest first, so `newest` is the thread just created by new_chat)
- `render_click(view, "delete_chat", %{"id" => newest.id})`
- assert [remaining] = Chat.list_conversations(work.id)
- assert remaining.id == a.id
- 3 assertions.

#### test "a thread from another draft cannot be switched to"  (context `%{conn: conn, work: work, user: user}`)
- `{:ok, other} = Works.create_work(user.id, %{"title" => "Other", "body" => String.duplicate("w ", 300)})`; `{:ok, theirs} = Chat.get_or_create_conversation(other.id)`
- mount `/works/<work.slug>?chat=1`; `render_click(view, "switch_chat", %{"id" => theirs.id})`
- refute Chat.get_conversation(work.id, theirs.id)   (`Chat.get_conversation/2`: work id, conversation id; returns nil when the conversation belongs to another work)
- 1 assertion. (Also implies the click must not crash the LiveView.)

### describe "carrying a passage into the question"

All five tests mount `live(conn, ~p"/works/#{work.slug}?chat=1")`.

#### test "a real selection is kept, verbatim from the draft"
- `html = render_click(view, "add_context", %{"text" => "  The kettle went cold on the counter "})` (note leading two spaces and one trailing space: the text is trimmed)
- assert html =~ "Carrying 1 passage"
- assert html =~ "The kettle went cold on the counter"
- 2 assertions.

#### test "a selection that is not in the draft is refused"
- `html = render_click(view, "add_context", %{"text" => "a sentence the writer never wrote"})`
- refute html =~ "Carrying"
- 1 assertion.

#### test "a stray click adds nothing"
- refute render_click(view, "add_context", %{"text" => "the"}) =~ "Carrying"   (a very short selection, "the", is refused even though it occurs in the draft)
- 1 assertion.

#### test "the same passage twice is carried once"
- `render_click(view, "add_context", %{"text" => "The kettle went cold on the counter"})`, then again identical, `html` from the second call.
- assert html =~ "Carrying 1 passage"
- 1 assertion.

#### test "it can be dropped again"
- add the passage "The kettle went cold on the counter"; `html = render_click(view, "drop_context", %{"i" => "0"})` (index as string "0")
- refute html =~ "Carrying"
- 1 assertion.

Behavior not obvious from the code:
- The composer (and drawer) only render when `:deepseek_api_key` is set; hence `async: false` and the put_env with restore. This is the only LLM-related seam in the file; no request is ever sent.
- `Chat.get_or_create_conversation/1` returns the work's existing conversation or creates one; `new_chat` creates an additional conversation (newest first in `list_conversations/1`), becomes the current thread, shows an empty transcript with the placeholder text "What is actually on the page", and keeps the old thread on the thread strip (class `mg-thread on` marks the current one) titled by its first user message.
- Deleting the current thread leaves one remaining (the older one).
- Passage carrying: the selection is trimmed, must appear verbatim in the draft, and a stray selection ("the") is refused (the handler asks `Marginalia.Reading.cite(work, text)`; nil means ignored; the lib keeps at most 6 passages, deduplicated by text); duplicates are deduplicated; the banner reads "Carrying 1 passage"; `drop_context` takes the index.

# =====================================================================
# ROUTE GROUP F: /drafts/:slug and /drafts/:slug/changes (public draft view)
# =====================================================================

## test/marginalia_web/live/draft_render_test.exs  (4 tests; covers the public `/drafts/:slug` page and `/drafts/:slug/changes`)

Module `MarginaliaWeb.DraftRenderTest`. Moduledoc: "What a reader sees of a draft stored one sentence per line: paragraphs, and nothing between the sentences of one." Alias `Marginalia.Works`.

### Shared setup
`setup do` (no conn used):
1. `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
2. `owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})` (the configured owner email from config, not overridden here).
3. Body (exact concatenation):
```
"# The post\n\nAt 04:47 UTC agent-7 implemented the Guideline step\nreset for lock delay. " <>
"The idea came from agent-8.\n\n> agent-8 logged that the cap locks a piece. Agent-7\n> read it.\n\n" <>
"```\nline one\nline two\n```\n\n- one. Two.\n- three.\n\nEvery node, by minute. " <>
String.duplicate("word ", 200)
```
Expanded: heading `# The post`; paragraph "At 04:47 UTC agent-7 implemented the Guideline step" newline "reset for lock delay. The idea came from agent-8."; blockquote lines "> agent-8 logged that the cap locks a piece. Agent-7" / "> read it."; fenced code block with lines "line one", "line two"; list items "- one. Two." and "- three."; final paragraph "Every node, by minute. " followed by "word " x200.
4. `{:ok, work} = Works.create_work(owner.id, %{"title" => "The post", "body" => body})`. Context `%{work: work}`. Note work status is not set to "read" and no login: the view is anonymous (`build_conn()`).

### test "sentences of a paragraph run on; the draft's blank lines are the only breaks"
- `{:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}")` -> `/drafts/<slug>`
- refute html =~ "<br"
- assert html =~ "<p>At 04:47 UTC agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8.</p>"
  (The raw line wrap "step\nreset" is joined with a space; the sentence boundary after "delay." is a literal newline character `\n` inside the `<p>`, not a `<br>`.)
- 2 assertions.

### test "a blockquote renders as one quoted paragraph"
- visit `/drafts/<slug>`.
- `[quote] = Regex.run(~r/<blockquote>.*?<\/blockquote>/s, html)` (match must succeed; first blockquote)
- assert quote =~ "<p>agent-8 logged that the cap locks a piece.\nAgent-7 read it.</p>"   (again sentence boundary is `\n`; the source line wrap "Agent-7\n> read it." becomes "Agent-7 read it." joined across the `>` marker)
- refute quote =~ "<br"
- 2 assertions.

### test "code keeps its line breaks and a list keeps its items"
- visit `/drafts/<slug>`.
- assert html =~ "<code>line one\nline two\n</code>"
- assert html =~ "<li>one. Two.</li>"   (a list item with two sentences stays on one line, no split)
- assert html =~ "<li>three.</li>"
- 3 assertions.

### test "the changes page shows the sentence that changed, on its own"
- `[s] = Works.list_sections(work.id)` (exactly one section)
- `para = s.body |> String.split("\n\n") |> Enum.find(&String.contains?(&1, "from agent-8."))`
- `{:ok, _} = Works.replace_block(s, para, String.replace(para, "from agent-8.", "from agent-8's decision."))`
- `{:ok, _view, html} = live(build_conn(), ~p"/drafts/#{work.slug}/changes")` -> `/drafts/<slug>/changes`
- assert html =~ "1 edited"
- `[row] = Regex.run(~r/<div class="mg-diff-row change">.*?<\/div>\s*<\/div>/s, html)` (match must succeed)
- assert row =~ ~s(class="w ins")
- assert row =~ "decision."
- assert row =~ ~s(class="w del")
- 4 assertions.

Behavior not obvious from the code:
- Drafts are stored one sentence per line (recent commits: "drafts: one sentence per line, on arrival and on every edit", "a draft's sentences render as one paragraph, and only a blank line breaks it"). Rendering must therefore not turn those newlines into `<br>`: within a paragraph the raw newline between sentences is kept as a literal "\n" in the HTML text, and hard-wrapped lines inside a sentence are joined with a single space.
- Blockquote: `> ` markers are stripped per line, all lines form one `<p>` inside `<blockquote>`.
- Fenced code keeps its line breaks and gets a trailing newline inside `<code>` (`<code>line one\nline two\n</code>`; no language class/`<pre>` is asserted).
- List items are not split on sentence boundaries: `<li>one. Two.</li>`.
- The changes page (`/drafts/:slug/changes`) is public (anonymous), renders per-sentence diff rows (`<div class="mg-diff-row change">`) where the edited sentence alone is shown with `<span class="w del">`/`<span class="w ins">` word marks, and the count text "1 edited".

TOTALS: tests=95 assertions=223 (assert/refute calls recorded; counts match grep of assert/refute lines per file)

| file | tests | assertions |
|---|---|---|
| case_index_test.exs | 22 | 57 |
| case_page_test.exs | 8 | 20 |
| case_read_test.exs | 22 | 56 |
| cases_tour_test.exs | 12 | 28 |
| changes_tab_test.exs | 7 | 17 |
| cluster_view_test.exs | 4 | 8 |
| confirm_gate_test.exs | 6 | 9 |
| draft_render_test.exs | 4 | 11 |
| drawer_test.exs | 10 | 17 |

# PART 6. Web, import/inline thread/landing/link chat and flow

# D2: LiveView tests (import, inline thread, landing, link, link chat)

Conventions: all paths relative to test/marginalia_web/live/. `html` means the string returned by the LiveViewTest call. `~p` sigils resolved to paths.

---

## import_flow_test.exs  (25 tests; covers live view at route /import: GitHub bulk-import wizard, FakeHub stub)

Module: MarginaliaWeb.ImportFlowTest. `use MarginaliaWeb.ConnCase, async: false`; imports Phoenix.LiveViewTest, Marginalia.AccountsFixtures; alias Marginalia.Works.

Moduledoc (reason for the file): "The bulk import, end to end, with GitHub stubbed out. What is under test is the flow: that listing is a separate step from importing, that nothing is created until somebody has seen the list, and that the three ways of choosing -- a search, a title regex, the boxes -- compose instead of fighting. None of that is about HTTP, and a test that needed a token would not run. The stub is deliberately dumb. It answers with fixed rows and records what it was asked for, because the questions worth asking here are 'was the right set carried from the choosing step to the import step' and 'what does the page do when one of them cannot be fetched'." (The stub in fact records nothing; it only answers.)

### Stub / seam: FakeHub (nested module defined in the test file)
Installed in setup via `Application.put_env(:marginalia, :github_api, FakeHub)`; previous value restored in `on_exit` (`Application.put_env(:marginalia, :github_api, previous)`). So the app reads the module from config key `:github_api` and calls these functions on it:

- `FakeHub.rows/0` -> the `@rows` list (used by tests).
- `FakeHub.list(owner, repo, _token, _opts \\ [])` -> `{:ok, rows}` with each row built by `row("#{owner}/#{repo}", r)`.
- `FakeHub.search(query, token, opts \\ [])`:
  - `search("boom" <> _, _token, _opts)` -> `{:error, :forbidden}`
  - any other query -> `{:ok, rows}` each built with repo `"found/elsewhere"`.
- `FakeHub.documents(candidates, _token, opts \\ [])`: `total = length(candidates)`; splits candidates into `bad` (number == 7) and `good`; for each good candidate calls `opts[:on_item].(c, total)` if `is_function(opts[:on_item])`; returns `%{documents: docs, failed: Enum.map(bad, &{&1, :not_found})}`. Each doc is `%{number: c.number, repo: c.repo, title: c.title, body: "# #{c.title}\n\n" <> String.duplicate("word ", 80), source_url: c.url}`. Comment: "#7 is the one that cannot be fetched, so every test has a named failure available without arranging one".
- Rows (`@rows`), comment: "deliberately not in merge order: GitHub answers newest first, and the page has to put them back into the order they happened in":

| number | title | state | draft | merged-at date |
|---|---|---|---|---|
| 9 | "Fix the parser" | "merged" | false | "2025-04-01" |
| 8 | "Revert the fix" | "open" | false | nil |
| 7 | "Add a test" | "closed" | true | "2025-02-01" |
| 6 | "Nothing to do with it" | "open" | false | "2025-03-01" |

- `row(repo, r)` produces: `%{repo: repo, number: r.number, title: r.title, url: "https://example.invalid/#{repo}/pull/#{r.number}", state: r.state, draft: r.draft, base: "main", head: "b#{r.number}", updated_at: "2026-01-01T00:00:00Z", created_at: "2025-01-01T00:00:00Z", merged_at: r.at && r.at <> "T00:00:00Z"}` (merged_at is nil when `at` is nil). Note the timestamps are ISO strings, not DateTime structs.

### Setup (every test)
`user = user_fixture()`; returns `%{conn: log_in_user(conn, user), user: user}`. So all tests are logged in as an owner with no works; no folders pre-created.

### Helper `to_listing(view)`
```
render_click(view, "source", %{"to" => "github"})
render_submit(view, "find", %{"mode" => "repo", "repo" => "temper/blimp", "token" => "t"})
render_async(view)
```
Returns the html from `render_async`. After this the view is on the "Choose" step with all 4 rows listed with repo "temper/blimp" and all selected (4 selected).

Event names used on the view: "source" (%{"to" => "github"|"files"}), "find" (submit), "pattern" (change and submit; params "how" = "regex"|"query", "pattern"), "toggle" (%{"key" => "temper/blimp#6"}), "settings" (change; "folder", "commits", "number"), "import" (submit, %{}), "none", "all", "back", "order" (change and submit; %{"order" => "newest"}). Row elements carry attribute `phx-value-key="temper/blimp#N"`. Selected count is rendered as `<b>N selected</b>`.

### test "the first step is a choice of source, and creates nothing"
- Visit `live(conn, ~p"/import")` -> /import; `{:ok, _view, html}`.
- assert html =~ "Pull requests"
- assert html =~ "Files"
- assert `Works.list_works(user.id) == []`
(3 assertions)

### test "finding lists the pull requests without importing any"
- live /import; `html = to_listing(view)`.
- `for row <- FakeHub.rows(), do: assert(html =~ row.title)` -> each of "Fix the parser", "Revert the fix", "Add a test", "Nothing to do with it" present (1 assert line, 4 executed).
- assert html =~ "<b>4 selected</b>"
- comment: "the whole point of the step: a listing is not an import"; assert `Works.list_works(user.id) == []`.
(3 assert lines, 6 executed)

### test "a title regex filters the list and sets the selection"
- live /import; to_listing(view).
- `html = render_change(view, "pattern", %{"how" => "regex", "pattern" => "fix"})`
- assert html =~ "Fix the parser"
- assert html =~ "Revert the fix"
- refute html =~ "Nothing to do with it"
- assert html =~ "<b>2 selected</b>"
(4 assertions; regex matching is case-insensitive in effect, "fix" matches "Fix the parser". "Add a test" is not asserted.)

### test "a pattern that will not compile says so and keeps the list"
- live /import; to_listing.
- `html = render_change(view, "pattern", %{"how" => "regex", "pattern" => "(unclosed"})`
- assert html =~ "Fix the parser", "a half-typed pattern should not empty the page"
- assert html =~ "missing closing parenthesis" or html =~ "unmatched"  (error text comes from the host regex engine; either wording accepted)
(2 assertions)

### test "the boxes have the last word over the regex"
- live /import; to_listing.
- render_change "pattern" `%{"how" => "regex", "pattern" => "fix"}` (selects #9 and #8).
- comment: "put one back that the pattern did not match"; `render_click(view, "toggle", %{"key" => "temper/blimp#6"})`.
- `render_change(view, "settings", %{"folder" => "Picked", "commits" => "false"})`
- `render_submit(view, "import", %{})`; `render_async(view)`.
- `titles = user.id |> Works.list_works() |> Enum.map(& &1.title) |> Enum.sort()`
- assert titles == ["Fix the parser", "Nothing to do with it", "Revert the fix"]
(1 assertion)

### test "clearing and selecting work on what is shown, not on everything"
- live /import; to_listing; render_change "pattern" regex "fix".
- assert render_click(view, "none", %{}) =~ "<b>0 selected</b>"
- comment: `"all" means all *shown*, so the two the pattern hid stay out`; assert render_click(view, "all", %{}) =~ "<b>2 selected</b>"
(2 assertions)

### test "importing lands them in a folder and says what could not be fetched"
(multi-line head: `%{conn: conn, user: user}`)
- live /import; to_listing.
- render_change "settings" `%{"folder" => "temper/blimp", "commits" => "true"}`; render_submit "import" %{}; `html = render_async(view)`.
- assert html =~ "3 drafts imported"
- assert html =~ "Could not be fetched"
- assert html =~ "Add a test"   (the failed #7 is named)
- `works = Works.list_works(user.id)`; assert length(works) == 3
- assert Enum.all?(works, &(&1.folder_id != nil))
- refute Enum.any?(works, &(&1.title == "Add a test"))
(6 assertions)

### test "a second import into the same folder skips what is there"
- `run = fn -> {:ok, view, _} = live(conn, ~p"/import"); to_listing(view); render_change(view, "settings", %{"folder" => "temper/blimp"}); render_submit(view, "import", %{}); render_async(view) end` (same `conn`, fresh LiveView each call).
- `run.()`; `html = run.()`.
- assert html =~ "0 drafts imported" or html =~ "already in the folder"
- assert length(Works.list_works(user.id)) == 3
(2 assertions)

### test "a search that GitHub refuses is reported in words"
- live /import; render_click "source" `%{"to" => "github"}`.
- render_submit "find" `%{"mode" => "search", "query" => "boom", "token" => "t"}`; `html = render_async(view)`. (FakeHub.search returns `{:error, :forbidden}`.)
- assert html =~ "GitHub refused"
- refute html =~ "Fix the parser"
(2 assertions)

### test "a search lists across repositories"
- live /import; source github; render_submit "find" `%{"mode" => "search", "query" => "label:design", "token" => "t"}`; render_async.
- assert html =~ "found/elsewhere"
- assert html =~ "Fix the parser"
(2 assertions)

### test "a repository written wrongly is refused before any request"
- live /import; source github.
- `html = render_submit(view, "find", %{"mode" => "repo", "repo" => "blimp", "token" => "t"})` (no render_async; the synchronous render must already contain the error).
- assert html =~ "owner/name"
(1 assertion)

### test "the token is never rendered back into the page"
- live /import; source github.
- render_submit "find" `%{"mode" => "repo", "repo" => "temper/blimp", "token" => "ghp_secret_do_not_print"}`.
- `html = render_async(view)`; refute html =~ "ghp_secret_do_not_print"
- render_change "settings" `%{"folder" => "x"}`; render_submit "import" %{}; refute render_async(view) =~ "ghp_secret_do_not_print"
(2 assertions)

### test "the file step is reachable and starts empty"
- live /import; `html = render_click(view, "source", %{"to" => "files"})`.
- assert html =~ "Drop up to"
- assert html =~ "Import 0"
(2 assertions)

### test "back walks the steps rather than reloading"
- live /import; to_listing.
- assert render_click(view, "back", %{}) =~ "GitHub token"   (back from listing to the token/repo form)
- assert render_click(view, "back", %{}) =~ "Pull requests"   (back to source choice)
(2 assertions)

### test "the list is oldest first, so the folder reads forwards"
- live /import; `html = to_listing(view)`.
- `order = Regex.scan(~r/phx-value-key="temper\/blimp#(\d+)"/, html) |> Enum.map(fn [_, n] -> n end)`
- comment: "#7 merged February, #6 March, #9 April; #8 never merged, so it sorts by when it was opened, which is before all of them" (created_at 2025-01-01 for all rows).
- assert order == ["8", "7", "6", "9"]
(1 assertion. Sort key = merged_at, falling back to created_at when not merged; ascending. The key attributes appear in the DOM in this order.)

### test "the order can be flipped, and numbering follows it"
- live /import; to_listing.
- render_change "order" `%{"order" => "newest"}`; render_change "settings" `%{"folder" => "Backwards", "number" => "true"}`; render_submit "import" %{}; render_async.
- titles sorted (string sort) of all works.
- comment: "#7 cannot be fetched, so the three that land are 9, 6, 8 in that order"
- assert titles == ["1. Fix the parser", "2. Nothing to do with it", "3. Revert the fix"]
(1 assertion. Titles are prefixed "N. " by position in the chosen order; newest-first gives #9 -> 1, #6 -> 2, #8 -> 3; failed #7 does not consume a number.)

### describe "the query box"  (5 tests; same outer setup)

#### test "narrows by state without another request"
- to_listing; `html = render_change(view, "pattern", %{"how" => "query", "pattern" => "state:open"})`
- comment "#8 and #6 are the open ones in the stub".
- assert html =~ "Revert the fix"; assert html =~ "Nothing to do with it"; refute html =~ "Fix the parser"; assert html =~ "<b>2 selected</b>"
(4 assertions; "Revert the fix" does not contain "Fix the parser" (case differs) so the refute is safe)

#### test "the shape from the report"
- to_listing; render_change "pattern" `%{"how" => "query", "pattern" => "is:pr state:merged"}`
- assert html =~ "Fix the parser"; assert html =~ "<b>1 selected</b>"
(2 assertions)

#### test "a bare word still matches the title, and a minus takes it away"
- to_listing.
- assert render_change(view, "pattern", %{"how" => "query", "pattern" => "fix"}) =~ "<b>2 selected</b>"
- assert render_change(view, "pattern", %{"how" => "query", "pattern" => "-fix"}) =~ "<b>2 selected</b>"
(2 assertions; "-fix" excludes titles containing fix, leaving "Add a test" and "Nothing to do with it". Bare word matching is case-insensitive.)

#### test "a typo is refused by name and the list is kept"
- to_listing; `html = render_change(view, "pattern", %{"how" => "query", "pattern" => "stat:closed"})`
- comment: "the important half: it did not quietly mean nothing"
- assert html =~ "do not know"; assert html =~ "stat"
- assert html =~ "Fix the parser", "the list stays while the query is wrong"
- assert html =~ "<b>4 selected</b>", "and so does the selection"
(4 assertions)

#### test "switching language re-runs the same text"
- to_listing.
- comment "a regex that is a bare word in the other language".
- assert render_change(view, "pattern", %{"how" => "regex", "pattern" => "fix|test"}) =~ "<b>3 selected</b>"   (matches Fix the parser, Revert the fix, Add a test)
- assert render_change(view, "pattern", %{"how" => "query", "pattern" => "fix|test"}) =~ "<b>0 selected</b>"   (in query language "fix|test" is a single bare word matched literally against titles)
(2 assertions)

### describe "pressing Enter in a filter box"  (4 tests)

#### test "re-applies the filter instead of reloading the page"
- to_listing; render_change "pattern" `%{"how" => "query", "pattern" => "state:merged"}`.
- comment: "what Enter does to a form that has a phx-submit: the same event, and crucially not a GET that remounts the view and loses the listing"
- `html = render_submit(view, "pattern", %{"how" => "query", "pattern" => "state:merged"})` (so "pattern" must be handled as both phx-change and phx-submit)
- assert html =~ "Fix the parser"; assert html =~ "<b>1 selected</b>"
- assert html =~ "Choose", "still on the choosing step"
- refute html =~ "Pull requests", "a remount would put us back on the source step"
(4 assertions)

#### test "the order form survives it too"
- to_listing; `html = render_submit(view, "order", %{"order" => "newest"})`
- assert html =~ "Fix the parser", "the listing is still here"; assert html =~ "<b>4 selected</b>"
(2 assertions; "order" must also be handled as a submit event)

#### test "an empty query explains itself when it is the guessable mistake"
- to_listing; `html = render_change(view, "pattern", %{"how" => "query", "pattern" => "created:@today-90d"})`
- assert html =~ "Nothing matches that query"
- assert html =~ "that one day"
- assert html =~ "created:&gt;@today-90d" or html =~ "created:>@today-90d"   (the hint suggests writing `created:>@today-90d`; HTML-escaped or not accepted)
(3 assertions)

#### test "and says nothing when the query is simply too narrow"
- to_listing; render_change "pattern" `%{"how" => "query", "pattern" => "nonesuch"}`
- assert html =~ "Nothing matches that query"; refute html =~ "that one day"
(2 assertions)

### Behavior not obvious from the code:
- The wizard has steps: source -> github form (repo or search, plus token) -> choosing/listing -> import result. "back" from listing returns to the github form (contains "GitHub token"), second "back" to source (contains "Pull requests").
- Listing and importing are separate: find lists via `FakeHub.list`/`search`, never creates works; import fetches bodies via `FakeHub.documents` and creates works.
- Import is async: `render_submit "import"` then `render_async(view)`; "find" likewise is async for the network part, except repo-format validation ("owner/name") which is synchronous.
- Order: ascending by merged_at else created_at; reversible with "order" => "newest". Numbering ("number" => "true") prefixes "N. " to titles following the chosen order.
- Settings fields: "folder" (folder name; works are placed in it, `folder_id != nil`), "commits" ("true"/"false"; no visible effect asserted), "number".
- A second import to the same folder is idempotent (skips already-present drafts); result shows "0 drafts imported" or "already in the folder".
- Token must never appear in rendered HTML at any step, including after import.
- Selection semantics: pattern sets selection to the matching rows; "toggle" overrides afterwards ("the boxes have the last word"); "all" selects shown rows only; "none" clears.
- Regex errors and query typos keep the list and selection intact and show an error message ("do not know" + the offending key for query typos; compile error text for regex).
- Switching "how" re-runs the same pattern text in the other language.
- Failed fetches (#7) are reported under a heading containing "Could not be fetched" with the title.
- The two-case "or" assertions (regex error wording; "0 drafts imported" / "already in the folder"; escaped `>`) mean either wording passes.

---

## inline_thread_test.exs  (9 tests; covers read view /works/:slug?view=read, events open_thread/close_thread/resolve_thread/thread_send, Marginalia.Chat thread-by-block functions)

Module: MarginaliaWeb.InlineThreadTest. `use MarginaliaWeb.ConnCase, async: false` (comment: "not async: the composer only renders with a key configured, which is global config"). Imports Phoenix.LiveViewTest, Marginalia.AccountsFixtures; alias Marginalia.{Chat, Works}.

Moduledoc: "A conversation pinned to one paragraph, opened where that paragraph is. The property that makes it a margin rather than a text box: come back to the same paragraph and the same thread is still there."

### Setup (every test)
- Seam: `Application.put_env(:marginalia, :deepseek_api_key, "test-key")` with `on_exit` restoring the previous value. (No LLM is actually called; the key only makes the composer render.)
- `user = user_fixture()`
- body:
```
"# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\n" <>
"The kettle went cold on the counter, and nobody moved to fill it again.\n\n" <>
String.duplicate("word ", 260)
```
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`
- `{:ok, work} = Works.set_status(work, "read")`
- `section = hd(Works.list_sections(work.id))`
- returns `%{conn: log_in_user(conn, user), work: work, section: section, user: user}`.
- Block refs are of form "s1p1", "s1p2" (section 1, paragraph n); DOM ids `block-s1p2`.

Helper: `open(view, ref, section)` = `render_click(view, "open_thread", %{"ref" => ref, "section" => section.id})`.

### test "every block offers a thread, silently until you go near it"
- `live(conn, ~p"/works/#{work.slug}?view=read")` -> /works/<slug>?view=read; initial html.
- assert html =~ ~s(class="mg-tick")
- assert html =~ ~s(phx-click="open_thread")
- comment "the affordance is per block, so there is one per paragraph"; assert `html |> String.split(~s(phx-click="open_thread")) |> length() > 3` (at least 3 occurrences)
(3 assertions)

### test "opening one shows it under that paragraph and nowhere else"
- live read view; `html = open(view, "s1p2", s)`
- assert html =~ "on this paragraph"
- assert html =~ "What about this paragraph?"
- assert html =~ ~s(id="block-s1p2")
- comment "exactly one panel is open"; assert `html |> String.split("mg-thread-panel") |> length() == 2` (exactly one occurrence of "mg-thread-panel")
(4 assertions)

### test "coming back to the same paragraph returns to the same thread"
- live read view; open "s1p2"; `[first] = Chat.threads_by_block(work.id) |> Map.values()` (exactly one thread exists after opening; threads_by_block returns map block_ref => thread).
- `render_click(view, "close_thread", %{})`; open "s1p2" again.
- `threads = Chat.threads_by_block(work.id)`
- assert map_size(threads) == 1, "a second thread must not appear beside the first"
- assert threads["s1p2"].id == first.id
(2 assertions)

### test "a different paragraph gets its own thread"
- live read view; open "s1p1"; open "s1p2" (without closing).
- assert map_size(Chat.threads_by_block(work.id)) == 2
(1 assertion)

### test "a selection pins the thread to the passage, not just the paragraph"
- live read view; `html = render_click(view, "open_thread", %{"ref" => "s1p2", "section" => s.id, "quote" => "The kettle went cold on the counter"})`
- assert html =~ "on this passage"
- assert html =~ "The kettle went cold on the counter"
- assert `Chat.threads_by_block(work.id)["s1p2"].quote == "The kettle went cold on the counter"`
(3 assertions)

### test "the tick carries the thread's message count"
- live read view; open "s1p2"; `thread = Chat.threads_by_block(work.id)["s1p2"]`.
- `Chat.append(thread.id, "user", "what is this doing")`; `Chat.append(thread.id, "assistant", "holding the room still")`
- Fresh mount: `{:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")`
- assert html =~ "2 in this thread"
- assert html =~ "has-thread"
(2 assertions; Chat.append/3 args: thread id, role, content)

### test "a thread can be settled and reopened"
- live read view; open "s1p2"; thread; `Chat.append(thread.id, "user", "said something")`; open "s1p2" again.
- assert render_click(view, "resolve_thread", %{}) =~ "settled"
- assert Chat.threads_by_block(work.id)["s1p2"].resolved
- `render_click(view, "resolve_thread", %{})` (toggle)
- refute Chat.threads_by_block(work.id)["s1p2"].resolved
(3 assertions)

### test "pinned threads stay out of the drawer's strip"
- live read view; open "s1p2".
- comment "the drawer lists whole-draft conversations only"
- assert Enum.all?(Chat.list_conversations(work.id), &(&1.anchor_kind == "work"))
- assert Enum.all?(Chat.conversation_summaries(work.id), &is_map/1)
(2 assertions; both are vacuously true if the lists are empty)

### test "a link-holder can read a thread but not add to it"
- Owner: live read view; open "s1p2"; thread; `Chat.append(thread.id, "user", "the owner said this")`.
- Visitor: `visitor = get(build_conn(), ~p"/works")` (an unauthenticated conn that was handed a session, i.e. a guest), `{:ok, vview, _} = live(visitor, ~p"/works/#{work.slug}?view=read")`.
- `html = render_click(vview, "open_thread", %{"ref" => "s1p2", "section" => s.id})`
- assert html =~ "the owner said this"
- refute html =~ "What about this paragraph?"   (composer prompt not shown to visitor)
- `render_click(vview, "thread_send", %{"message" => "let me in"})`
- assert Chat.history(thread.id) |> length() == 1   (the visitor's message was not appended)
(3 assertions; `get(build_conn(), ~p"/works")` implies GET /works for a logged-out conn must succeed (guest minting or redirect) and yield a conn usable by `live/2`)

### Behavior not obvious from the code:
- One thread per (work, block ref): reopening returns the same thread; a different ref makes a new thread.
- Opening with "quote" sets `thread.quote` and the panel says "on this passage" rather than "on this paragraph".
- The tick shows "N in this thread" and class "has-thread" when the thread has messages.
- Resolving toggles `resolved` and the panel shows "settled".
- Non-owner visitors may read but "thread_send" is ignored (no error asserted).
- `Chat.threads_by_block/1` is keyed by string block ref; values have `id`, `quote`, `resolved`. `Chat.list_conversations/1` rows have `anchor_kind` ("work" for whole-draft; pinned threads use another kind).

---

## landing_features_test.exs  (34 tests; covers homepage live view at route "/" (MarginaliaWeb.LandingLive), plus source-reading consistency checks against lib files and the router)

Module: MarginaliaWeb.LandingFeaturesTest. `use MarginaliaWeb.ConnCase, async: true`; imports Phoenix.LiveViewTest. No user, no DB data.

Moduledoc: "The homepage describes what exists. A landing page drifts from the product silently: nothing breaks when a feature ships and the pitch does not mention it, and nothing breaks when the pitch keeps promising one that was removed. These are the claims worth pinning, and the links out of them have to actually resolve."

### Setup (outer, applies to every test including those in describe blocks)
```
{:ok, _view, html} = live(conn, ~p"/")        # GET /
%{html: flat(html), conn: conn}
```
`defp flat(html), do: String.replace(html, ~r/\s+/, " ")`. Comment: "HEEx wraps prose at the source margin, so a phrase in the rendered page can carry a newline and ten spaces in the middle of it." So `html` in every test is the rendered landing page with every run of whitespace collapsed to a single space. Tests that take only `%{html: html}` assert against this flattened text. Anonymous visitor (no login).

NOTE for reimplementation: several tests read the implementation's own source files (relative to cwd = project root): `lib/marginalia_web/live/landing_live.ex`, `lib/marginalia/chat/editor.ex`, `lib/marginalia/analysis/linker.ex`, `lib/marginalia/import/query.ex`, and `assets/css/app.css` is not read here. They also call `Phoenix.Router.route_info(MarginaliaWeb.Router, "GET", path, "example.com")` and `Marginalia.Chat.Editor.modes/0` and `Marginalia.Import.Query.filter/2`. These are structural tests whose form is tied to the Elixir source layout (regexes on source text) and will need an equivalent in the new implementation.

### test "it names the things that were built after it was written"
- assert html =~ "Where you are in twelve sections", "per-section and document summaries"
- assert html =~ "Every change, kept", "revisions, the diff and git"
- assert html =~ "read forwards", "stacks"
(3 assertions)

### test "the rewrite section is not still quoting an old limit"
- assert html =~ "2,500 words"
- refute html =~ "250 words", "the ceiling moved three times; the page must not keep the first one"
(2 assertions; note "2,500 words" does not contain the substring "250 words" because of the comma)

### test "it says what the whole-document pass actually does"
- assert html =~ "working under", "the decomposing prong"
- assert html =~ "never tell the second pass what the first concluded", "the prongs are independent"
(2 assertions)

### test "the git claim is specific rather than a metaphor"
- assert html =~ "git log -p"
- assert html =~ "one per draft"
(2 assertions)

### test "the numbers it cites are the real ones"
- assert html =~ "111 stacked pull requests"
- assert html =~ "It found sixty-five", "the chapters walked back by a later one"
(2 assertions)

### describe "the work it points at"
Comment on the describe: "Whether that slug is published is data, not code, and the test database has none -- so what is checked here is that the route exists and that the page it lands on behaves when the reading is absent, which is what a visitor gets if it is ever unpublished."

#### test "the published reading is a real route, and degrades when there is nothing there"
- assert `{:error, {:live_redirect, %{to: "/reading"}}} = live(conn, ~p"/reading/a-temper-backend-for-blimp-pull-request-stack")`  (missing slug live-redirects to /reading)
- `{:ok, _view, html} = live(conn, ~p"/reading")`; assert html =~ "Readings"  (this `html` is unflattened, shadowing the setup one)
(2 assertions)

#### test "the cases page resolves"
- `{:ok, _view, _html} = live(conn, ~p"/cases")` (mount must succeed; no other assertion)
(0 assertions; a successful match)

#### test "every link out of the page is one the router serves"
```
paths =
  Regex.scan(~r/href="(\/[^"#?]*)"/, html)
  |> Enum.map(fn [_, p] -> p end)
  |> Enum.uniq()
  |> Enum.reject(&String.starts_with?(&1, "/assets"))
```
- assert "/cases" in paths
- assert "/reading/a-temper-backend-for-blimp-pull-request-stack" in paths
- assert "/works/new" in paths
- for each path in paths: assert `Phoenix.Router.route_info(MarginaliaWeb.Router, "GET", path, "example.com") != :error`, message "#{path} is linked from the homepage and is not a route"
(3 + one per distinct local href; every root-relative href with query/fragment stripped, excluding /assets/*, must be a GET route)

### describe "the demos"

#### test "each major feature carries one"
- assert html =~ "Section 7 of 12, asked what is in it"
- assert html =~ "The Changes tab, after one accepted rewrite"
- assert html =~ "111 chapters, read forwards"
(3 assertions)

#### test "a demo's final frame is in the markup, not assembled by the script"
Comment: "The page has to read correctly with the script dead or motion turned down. Only `reveal-ready` -- which JS adds -- ever hides anything."
- assert html =~ "temper_date"
- assert html =~ "cuts the gloss"
- assert html =~ "65 of the 111 are walked back by a later chapter"
(3 assertions)

#### test "the steps are declared in the markup for the hook to walk"
- assert html =~ ~s(data-demo)
- assert html =~ ~s(data-step="1")
- assert html =~ ~s(data-step="4")
(3 assertions)

#### test "the diff demo marks removals and additions the same way the real one does"
- assert html =~ "<del", "removed words"
- assert html =~ "<ins", "added words"
(2 assertions)

#### test "nothing is hidden without the class the script adds"
No setup html used (takes no args but outer setup still runs). Reads source:
```
source = File.read!("lib/marginalia_web/live/landing_live.ex")
hiding =
  Regex.scan(~r/^\s*(\.[a-z-]+[^{]*)\{[^}]*opacity:0/m, source)
  |> Enum.map(fn [_, sel] -> String.trim(sel) end)
```
- for each `sel` in hiding: assert `String.contains?(sel, "reveal-ready")`, message "#{sel} hides content without waiting for the script; a landing page that needs JS to show its own copy sometimes shows nothing"
(0..n assertions; vacuous if no CSS rule with `opacity:0` is found. Meaning: every CSS rule in the landing page's inline stylesheet that sets `opacity:0` (no space) must have a selector containing `reveal-ready`.)

### describe "the chat"

#### test "the page says the chat fetches rather than recalls"
- assert html =~ "It goes and looks"
- assert html =~ "the quote was fetched from your book"
(2 assertions)

#### test "it names the tools the chat really has"
Comment: "these are the actual function names in Marginalia.Chat.Editor"
- for tool <- ["search_manuscript", "read_passage", "find_exact"]: assert html =~ tool, "#{tool} is shown on the page and must exist in the editor"
(3 executed assertions)

#### test "every tool the page shows is one the editor defines"
```
source = File.read!("lib/marginalia/chat/editor.ex")
shown =
  Regex.scan(~r/<span class="tool">([a-z_]+)<\/span>/, html)
  |> Enum.map(fn [_, name] -> name end)
  |> Enum.uniq()
```
- refute shown == []
- for name in shown: assert source =~ ~s("name" => "#{name}"), "the homepage shows #{name} as a tool the chat calls, and it is not one"
(so landing markup must contain `<span class="tool">NAME</span>` elements, and each NAME must appear in editor.ex as the literal `"name" => "NAME"` -- a tool-definition map)

#### test "the three modes are the three that exist"
- `ids = Enum.map(Marginalia.Chat.Editor.modes(), & &1.label)` (modes/0 returns a list of maps with `:label`)
- for label in ids: assert html =~ label, "mode #{label} exists and the page does not mention it"
- assert length(ids) == 3
(3 + 1 executed assertions; labels not spelled out in the test)

#### test "overruling it is described, in both kinds"
- assert html =~ "misreading"
- assert html =~ "records a ruling"
(2 assertions)

### describe "the linkage preview"

#### test "the section is there with its demo"
- assert html =~ "Two drafts, and what runs between them"
- assert html =~ "A novel and the story it came out of"
(2 assertions)

#### test "every edge kind it shows is one the linker can emit"
```
source = File.read!("lib/marginalia/analysis/linker.ex")
[_, types] = Regex.run(~r/@types ~w\(([^)]+)\)/, source)
real = String.split(types)
shown =
  Regex.scan(~r/class="d-edge[^"]*"[^>]*><i>([a-z_]+)<\/i>/, html)
  |> Enum.map(fn [_, k] -> k end)
  |> Enum.uniq()
```
- refute shown == []
- for kind in shown: assert kind in real, "the homepage draws a #{kind} edge and the linker cannot produce one"
(Markup contract: elements `class="d-edge..."` ... `><i>KIND</i>`. Linker source declares `@types ~w(...)` of six words.)

#### test "it names all six kinds, since it claims there are six"
- same `real` extraction from linker.ex
- assert length(real) == 6, "the copy says six kinds"
- for kind in real: assert html =~ kind, "#{kind} exists and the page does not mention it"
(1 + 6 executed assertions. From link_chat_flow_test, `tension` is one of the kinds; `Marginalia.Analysis.Linker.types/0` returns them.)

#### test "the direction of an edge is part of the claim"
- assert html =~ "the direction is part of the claim"
- assert html =~ "not merely that the two are about fathers"
(2 assertions)

#### test "clusters are mentioned as what pairs become"
- assert html =~ "cluster"
(1 assertion)

### test "the demo blocks do not reuse a class the page already styles"
(top level, no html arg)
```
source = File.read!("lib/marginalia_web/live/landing_live.ex")
```
Comment: "`.demo` was already in use for the worked example further up the page. Styling my blocks with the same class silently restyled that one."
- refute source =~ ~s(class="demo" data-demo), "a demo block is using the page's pre-existing .demo class"
- ```
  duplicated =
    Regex.scan(~r/^\s{6}(\.[a-z][a-z0-9-]*)\{/m, source)
    |> Enum.map(fn [_, sel] -> sel end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_sel, n} -> n > 1 end)
  ```
- assert duplicated == [], "two top-level rules for the same class in one stylesheet: #{inspect(duplicated)}"
(2 assertions. In the source, top-level CSS rules are indented exactly 6 spaces and written `.class{`; no class may be defined twice at that indent.)

### describe "the import pipeline"

#### test "the section is there, with every stage"
- assert html =~ "Forty pull requests in, one edited draft out"
- for {stage, n} <- Enum.with_index(~w(find narrow land read compose edit condense compare), 1): assert html =~ "<b>#{n}</b> #{stage}", "stage #{n} (#{stage}) is missing from the pipeline"
  Exact strings (on flattened html): `<b>1</b> find`, `<b>2</b> narrow`, `<b>3</b> land`, `<b>4</b> read`, `<b>5</b> compose`, `<b>6</b> edit`, `<b>7</b> condense`, `<b>8</b> compare`.
(1 + 8 executed assertions)

#### test "every qualifier it shows is one Import.Query actually accepts"
Comment: "The page prints a query as if you could type it. If the parser stops knowing one of these words, the homepage is teaching a syntax error."
```
source = File.read!("lib/marginalia/import/query.ex")
[_, known] = Regex.run(~r/@qualifiers ~w\(([^)]+)\)/, source)
known = String.split(known)
shown =
  Regex.scan(~r/<code[^>]*>([a-z]+):/, html)
  |> Enum.map(fn [_, q] -> q end)
  |> Enum.uniq()
```
- refute shown == [], "the pipeline shows no query at all"
- Comment: "`stat:` is on the page on purpose -- it is the typo whose refusal the section is demonstrating. It has to stay unknown for that to mean anything, so it is asserted from both sides rather than skipped."
- assert "stat" in shown, "the worked example of a refused qualifier is gone"
- refute "stat" in known, "`stat` became real and the page now demonstrates nothing"
- for q <- shown -- ["stat"]: assert q in known, "the homepage shows `#{q}:` as if you could type it, and Import.Query does not know it"
(3 + n executed assertions. Page contains `<code ...>word:` snippets including one starting `stat:`.)

#### test "the query it prints really does what the page says it does"
Pure-function test of `Marginalia.Import.Query.filter/2` (rows, query_string):
```
row = fn n, title, state ->
  %{title: title, state: state, draft: false, number: n, base: "main", head: "x",
    repo: "notactuallytreyanastasio/temper-blimp",
    created_at: ~U[2026-09-01 00:00:00Z], updated_at: ~U[2026-09-02 00:00:00Z],
    merged_at: nil}
end
rows = [row.(3, "Bump deps", "closed"), row.(74, "A regex engine", "closed")]
```
Comment: "`state:closed -Bump keeps the regex engine and drops the dependency bumps` is a claim about a parser, so it is checked against the parser."
- assert `{:ok, [%{title: "A regex engine"}]} = Marginalia.Import.Query.filter(rows, "state:closed -Bump")`   (-Bump removes "Bump deps"; case-insensitive title match; note the DateTime fields here are structs, in contrast to ISO strings in import_flow_test)
- assert `{:error, msg} = Marginalia.Import.Query.filter(rows, "stat:closed")`
- assert msg =~ "stat", "the page promises the error names the word it did not know"
(3 assertions)

#### test "@today is claimed as the thing GitHub cannot do, and it parses"
- assert html =~ "@today"
- assert html =~ "no relative dates"
- assert `{:ok, _} = Marginalia.Import.Query.filter([], "created:>@today-30d")`  (empty list, query with relative date; must return {:ok, _})
(3 assertions)

#### test "the import route it points at is real and reachable without an account"
- `{:ok, _view, html} = live(conn, ~p"/import")` (conn not logged in; this html shadows setup html)
- assert html =~ "Find"
(1 assertion; /import mounts for an anonymous visitor, no redirect)

### describe "the anchors"
Comment: "A link to a feature is something somebody pastes into a message and then cannot re-send when it breaks. So the ids are named for the feature rather than the headline above it -- the headline is prose and gets reworded, and an id derived from it would rot on the first pass of copy editing without anything failing."

#### test "every section is addressable and no id is used twice"
```
sections = Regex.scan(~r/<section class="sec head"([^>]*)>/, html)
ids = Regex.scan(~r/<section class="sec head" id="([a-z-]+)"/, html) |> Enum.map(fn [_, id] -> id end)
```
- assert length(ids) == length(sections), "#{length(sections) - length(ids)} section(s) on the page cannot be linked to"
- assert ids == Enum.uniq(ids), "a repeated id sends two links to the same place: #{inspect(ids -- Enum.uniq(ids))}"
(2 assertions; every `<section class="sec head"` must have `id="..."` as its immediately following attribute, ids lowercase a-z and hyphens only; note: no assertion that sections is non-empty)

#### test "the features people will link at have the ids they were given"
- for {id, what} in [{"changes", "revisions, the split diff and git"}, {"summaries", "per-section and document summaries"}, {"links", "two drafts related"}, {"stacks", "a folder read forwards"}, {"graph", "what leads to what"}, {"rewrites", "the one place it writes"}]: assert html =~ ~s(id="#{id}"), "/##{id} is the link for #{what}"
(6 executed assertions)

### describe "the example documents"

All three tests use `seeits = Regex.scan(~r/class="seeit"><a[^>]*href="([^"]+)"/, html) |> Enum.map(&List.last/1)` (the href of the first anchor inside each element with `class="seeit"`, on the flattened html).

#### test "the feature sections point at something a stranger can open"
- assert length(seeits) >= 6, "a feature described and never shown is a claim"
- for path in seeits: assert `Phoenix.Router.route_info(MarginaliaWeb.Router, "GET", path, "example.com") != :error`, "#{path} is offered as an example and is not a route"
(1 + n assertions)

#### test "they are public routes, not ones behind a login"
Comment: "/works, /stacks and /links mint a guest or need an account. These four are the public faces. An example nobody can open is worse than none."
- `public = ~w(/drafts /cases /reading /linked)`
- for path in seeits: assert Enum.any?(public, &String.starts_with?(path, &1)), "#{path} is not on a public page"
(n assertions; every seeit href must start with /drafts, /cases, /reading or /linked)

#### test "each one is a different thing to look at"
- assert length(Enum.uniq(seeits)) >= 3, "six links to one document is one example wearing six hats"
(1 assertion)

### Behavior not obvious from the code:
- The whole file is a drift guard: the landing page copy, markup contract (classes `tool`, `d-edge`, `seeit`, `sec head`, `reveal-ready`, `data-demo`, `data-step`) and the linked routes are pinned. A rewrite must reproduce the exact copy strings quoted above (all on whitespace-flattened HTML) and the markup shapes the regexes expect.
- Routes the homepage links to and which must exist as GET routes: /cases, /reading/a-temper-backend-for-blimp-pull-request-stack, /works/new, plus all /drafts*, /cases, /reading*, /linked* example links and anything else root-relative on the page (except /assets).
- /reading/<unknown-slug> must live_redirect to /reading (not 404); /reading page contains "Readings"; /cases mounts; /import mounts anonymously and contains "Find".
- The source-reading tests ("nothing is hidden...", "every tool the page shows...", "every edge kind...", "it names all six kinds", "every qualifier...", "the demo blocks do not reuse...") couple the tests to Elixir module attributes (`@types ~w(...)`, `@qualifiers ~w(...)`) and file paths; the linker has exactly six edge types, one of which is "tension".
- The Import.Query language (also exercised in import_flow_test): qualifiers like `state:`, `is:`, `created:`; `-word` negation; bare words match titles; `@today` and `@today-30d` relative dates; unknown qualifier returns `{:error, message}` containing the unknown word.

---

## landing_live_test.exs  (14 tests; covers LandingLive at "/")

Module: MarginaliaWeb.LandingLiveTest. `use MarginaliaWeb.ConnCase, async: true`; imports Phoenix.LiveViewTest, Marginalia.AccountsFixtures. No setup block. Html here is NOT whitespace-flattened (so multi-word phrases asserted must be on one source line in the rendered page).

### test "renders the pitch and the promise"
- `{:ok, _view, html} = live(conn, ~p"/")`
- assert html =~ "Someone who has actually read the whole thing"
- assert html =~ "what a reader leaves in the margin"
- assert html =~ "It reads. You decide."
(3 assertions)

### test "the page describes the surfaces the product actually has"
- live "/"
- comment: "one section per surface -- a feature nobody can picture is one nobody asks for, and each of these shipped after the first version of this page"
- assert html =~ "The page, with its notes in the margin"
- assert html =~ "A thread on one paragraph"
- assert html =~ "What leads to what"
- assert html =~ "The one place it writes"
- assert html =~ "Then you change it yourself"
- comment "and the affordances inside them"
- assert html =~ "a hairline appears in the"
- assert html =~ "drawn to scale"
- assert html =~ "Connections"
- assert html =~ "Tensions"
(9 assertions)

### test "it does not promise it will never write, now that it sometimes does"
- live "/"
- comment: "Marginalia.Rewrite proposes prose, so the old blanket promise was a lie the moment it shipped. The claim has to be the narrow, true one."
- refute html =~ "It never writes a word of your book"
- assert html =~ "This is the only"
- assert html =~ "It never applies anything"
- assert html =~ "No prose you did not ask for"
(4 assertions)

### test "the privacy claim matches how drafts are actually protected"
- live "/"
- comment: "uploading needs no account and a draft is secret by link, not by account -- the page used to say nobody else could see your work"
- assert html =~ "No account to upload"
- assert html =~ "private to whoever holds its link"
- refute html =~ "nobody else here can see your work"
(3 assertions)

### test "is a single document, not a layout nested inside itself"
- `conn = get(conn, ~p"/")`; `body = html_response(conn, 200)` (plain controller-style GET of the dead render)
- comment: "the bare layout is a ROOT layout; naming it as the live layout too would render the whole page twice"
- assert `length(String.split(body, "<!DOCTYPE html>")) - 1 == 1`  (exactly one "<!DOCTYPE html>", case-sensitive)
(1 assertion)

### test "does not carry the scaffold auth menu, which would duplicate its own header"
(multi-line head `%{conn: conn}`)
- `body = conn |> get(~p"/") |> html_response(200)`
- assert body =~ "MARGINALIA" or body =~ "Marginalia"
- refute body =~ ~s(menu menu-horizontal)
(2 assertions)

### test "the margin carries the product's own notes on the pitch, including ones that argue with it"
- `{:ok, _view, html} = live(build_conn(), ~p"/")`
- comment: "the page is the demo: notes annotate the pitch rather than restating it"
- assert html =~ "annotating its own pitch"
- comment "and at least one of them pushes back on the copy"
- assert html =~ "they read as a contradiction"
- assert html =~ "This section argues with the one before it"
(3 assertions)

### test "a logged-out visitor's CTAs go straight at the upload -- no account needed"
- live(build_conn(), ~p"/")
- assert html =~ ~s(href="/works/new")
(1 assertion)

### test "a logged-in writer's CTAs go to the upload page, not back to registration"
- comment: "registration bounces a logged-in user home, so pointing the CTA there makes every button on the page a no-op -- the bug this guards"
- `conn = log_in_user(conn, user_fixture())`; `{:ok, _view, html} = live(conn, ~p"/")`
- assert html =~ ~s(href="/works/new")
- refute html =~ ~s(href="/users/register")
(2 assertions)

### test "the margin offers sign-up actions, not just commentary"
- live(build_conn(), ~p"/")
- assert html =~ "Find yours"
- assert html =~ "Try to break it"
- comment "every action lands on the upload, which no longer needs an account"
- assert html =~ ~s(href="/works/new")
(3 assertions)

### test "worked examples are present and play in sequence"
- live(build_conn(), ~p"/")
- assert html =~ "Which thread did I set up and never pay off?"
- assert html =~ "Rewrite my opening paragraph so it hits harder."
- comment "the turns are staggered by index, which is what makes them play out"
- assert html =~ ~s(style="--i:0")
- assert html =~ ~s(style="--i:2")
(4 assertions)

### test "everything that animates is marked for the scroll observer"
- live(build_conn(), ~p"/")
- comment: "if a note were not observed it would stay invisible forever"
- assert html =~ "data-reveal"
- `reveals = length(String.split(html, "data-reveal")) - 1`
- assert reveals >= 10, "expected the rail to be revealed progressively, got #{reveals}"
(2 assertions)

### test "just the notes drops the prose and keeps the rail"
- `{:ok, view, _html} = live(conn, ~p"/")`; `html = render_click(view, "toggle_notes")` (no params)
- assert html =~ "notes-only"
- comment "the notes survive the switch -- they are the whole point of the mode"
- assert html =~ "annotating its own pitch"
(2 assertions)

### test "a logged-in writer is pointed at their drafts instead of log in"
- `conn = log_in_user(conn, user_fixture())`; live "/"
- assert html =~ "Your drafts"
(1 assertion)

### Behavior not obvious from the code:
- The landing page is a LiveView at "/" that works for anonymous and logged-in users; CTA link target is always "/works/new" (never "/users/register" when logged in).
- Dead render (GET) must contain exactly one `<!DOCTYPE html>` and no `menu menu-horizontal` markup; page header text includes "MARGINALIA" or "Marginalia".
- Event "toggle_notes" toggles a class/state producing "notes-only" in the html.
- At least 10 occurrences of the string `data-reveal`; worked-example turns styled `style="--i:0"` ... `style="--i:2"` (index-staggered).
- Logged-in writers see "Your drafts" (instead of a log-in link).
- Copy strings are legal-ish claims that were corrected after earlier lies (privacy, "never writes"); the negative refutes pin old wording out.

---

## link_chat_flow_test.exs  (15 tests; covers live view /links/:id/read (the "follow" view of a linked pair) and its chat bubble/panel, plus a CSS structural check of assets/css/app.css)

Module: MarginaliaWeb.LinkChatFlowTest. `use MarginaliaWeb.ConnCase, async: false`; imports Phoenix.LiveViewTest, Marginalia.AccountsFixtures; alias Marginalia.{Links, Works}; alias Marginalia.Analysis.Linker. Module attribute `@quote "A sentence long enough"`.

Moduledoc: "The chat on the pairwise reading: opening it, asking, and what comes back. There were tests for `Links.Chat` and none for the page it lives on, so 'chat is broken' had nothing to fail against."

### Setup (outer; every test)
```
Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
user = user_fixture()
mk = fn title ->
  body = "# #{title}\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)
  {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
  {:ok, w} = Works.set_status(w, "read")
  s = hd(Works.list_sections(w.id))
  {:ok, n} = Works.insert_node(%{work_id: w.id, section_id: s.id, node_type: "beat",
                                 title: "a beat in #{title}", quote: @quote})
  {w, n}
end
{a, a_n} = mk.("First")
{b, b_n} = mk.("Second")
{:ok, l} = Links.get_or_create(a.id, b.id)
{:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree."})
Links.store_edges(l,
  [%{"from" => a_n.id, "to" => b_n.id, "type" => "tension", "why" => "They part."}],
  Linker.types())
%{conn: log_in_user(conn, user), link: l, a: a}
```
Seams: Repo sandbox in `{:shared, self()}` mode (so async tasks spawned by the LiveView can use the DB connection). No `put_env` of an API key in this file; the chat's LLM call goes to the test endpoint config (`llm_endpoints` http://127.0.0.1:1, refuses) and so takes the failure path (see "a failed answer says so..."). Each work: title "First"/"Second", body = `# <title>`, blank line, `A sentence long enough to be a section.`, blank line, 200 repetitions of "word ". Status "read". One node per work: node_type "beat", title "a beat in First"/"Second", quote "A sentence long enough". One link First<->Second, status "linked", summary "They disagree.", one edge from First's node to Second's node, type "tension", why "They part.".

Common route: `~p"/links/#{l.id}/read"` -> /links/<link id>/read, logged in as the owner of both drafts.

### test "the bubble is not offered underneath the tour card"
Comment above: "The tour card's veil covers the viewport above the bubble, so the bubble was visible, unclickable, and silent about it."
- `{:ok, view, html} = live(conn, ~p"/links/#{l.id}/read")`
- assert html =~ "fl-tour-veil", "the one-time card should be up on a first visit"
- refute html =~ "lc-bubble", "the chat bubble is under the veil and cannot be pressed"
- `html = render_click(view, "dismiss_tour", %{})`
- refute html =~ "fl-tour-veil"
- assert html =~ "lc-bubble"
(4 assertions)

### test "the bubble is on the page and opens the panel"
- live; `html = render_click(view, "dismiss_tour", %{})`
- assert html =~ ~s(phx-click="toggle_chat")
- refute html =~ ~s(class="lc-panel")
- `html = view |> element("button.lc-bubble") |> render_click()`
- assert html =~ ~s(class="lc-panel")
- assert html =~ ~s(phx-submit="chat_send")
(4 assertions)

### test "asking shows the question and that it is thinking"
- live; dismiss_tour; click `button.lc-bubble`.
- `html = view |> form("form[phx-submit=chat_send]", %{"message" => "What is the disagreement?"}) |> render_submit()`
- assert html =~ "What is the disagreement?"
(1 assertion; the test name says "and that it is thinking" but only the question text is asserted)

### test "a failed answer says so rather than vanishing"
- live; dismiss_tour; click bubble.
- submit form `form[phx-submit=chat_send]` with `%{"message" => "anything"}`.
- comment: "the endpoint in test goes nowhere, so this is the failure path"
- `html = render_async(view, 5_000)`
- assert html =~ "What is the disagreement?" or html =~ "anything"   (the user's message "anything" is still shown; the first alternative is a leftover)
- refute html =~ "lc-thinking", "it is still claiming to be thinking"
(2 assertions; after the async LLM call fails (connection refused at 127.0.0.1:1, no key) the thinking indicator class `lc-thinking` must be gone)

### describe "citing from the wide screen's strip"
Comment above the describe: "These were written as 'the phone's sheet', and that premise was wrong in a way that cost real breakage: `.fl-strip` is `display: none` under 1100px. The phone's UI is `.fl-sheet`/`.fl-stack`, whose cards the hook builds. The strip is the *wide* screen's card -- and because every assertion here only read server-rendered strings, nothing failed when the strip's entire stylesheet was left behind in the phone's media query and the button rendered as unstyled prose."

#### test "it offers a way into the chat, and no longer a x that did nothing"
- live; `html = render_click(view, "dismiss_tour", %{})`
- assert html =~ ~s(class="fl-strip-head")
- assert html =~ "ask about this"
- comment: "the hook pushes cite_edge with the edge it can see, so there is no server-owned phx-value for the browser to write on"
- refute html =~ "cite_current"
- comment: "Nothing on a wide screen dismisses the strip -- it follows the scroll -- so the strip has no close button any more. The phone's sheet, which genuinely can be dismissed, keeps its own; the markup is identical, so what to assert is that the page carries one of them now rather than two."
- assert `html |> String.split(~s(class="shut")) |> length() == 2`  (exactly one occurrence of `class="shut"` in the page)
(4 assertions)

#### test "citing an edge puts that connection into the chat and opens it"
- live; dismiss_tour (result ignored).
- `[edge | _] = Links.edges(hd(Links.for_work(a.id)))` (Links.for_work/1 returns the links of a work; Links.edges/1 takes a link and returns edge structs with `.id`)
- `html = render_click(view, "cite_edge", %{"edge" => to_string(edge.id)})`
- assert html =~ "lc-panel"
- assert html =~ "They part."   (the edge's `why` appears in the chat panel as the cited connection)
(2 assertions)

### describe "somewhere to start"

#### test "an empty chat offers questions rather than a blank box"
- live; dismiss_tour; `html = view |> element("button.lc-bubble") |> render_click()`
- assert html =~ ~s(class="lc-openers")
- assert html =~ "What does the second document already answer?"
(2 assertions)

#### test "tapping one asks it"
- live; dismiss_tour; click bubble.
- `html = view |> element(".lc-openers button", "Which connection is doing the most work?") |> render_click()` (element by selector `.lc-openers button` with text filter "Which connection is doing the most work?")
- assert html =~ "Which connection is doing the most work?"
- comment "and they go away once the conversation has started"
- refute html =~ ~s(class="lc-openers")
(2 assertions)

### describe "what the reference strip ships with"
Comment above: "Both layouts are a hook driving markup the server renders. The hook's own behaviour is guarded structurally in hooks_test; what the server owes it is this -- every part present, every part wired."

Describe-level setup (after outer setup):
```
{:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
%{html: render_click(view, "dismiss_tour", %{}), view: view}
```

#### test "the strip, the sheet, and the passage they exist to show"
- assert html =~ ~s(class="fl-mid")
- assert html =~ ~s(class="fl-strip")
- assert html =~ ~s(class="fl-sheet")
- comment: "the far document's own words. The strip hides these on a wide screen, where the column beside it is already showing them; the phone's sheet is the one that needs them carried across."
- assert html =~ ~s(class="far")
(4 assertions)

#### test "a head that says what this is"
- assert html =~ ~s(class="fl-strip-head")
- assert html =~ ~s(class="rel")
- assert html =~ ~s(class="nth")
(3 assertions)

#### test "and the way into the chat, since the drawn line is thin to hit"
- assert html =~ "ask about this"
(1 assertion)

#### test "the passages the hook needs to reach are addressable"
- comment "the hook copies the far passage out of the reference column by id"
- assert html =~ ~s(id="blk-other-)
- assert html =~ ~s(id="blk-lead-)
- comment "and finds what to show from the note data on each block"
- assert html =~ "data-peer-ref="
- assert html =~ "data-edge="
(4 assertions)

#### test "both columns are rendered, even though one is not shown"
- comment: "the reference column stays in the DOM on a phone: the sheet reads its text out of it. Hiding it with CSS is the point; removing it would take the passage with it."
- assert html =~ ~s(id="fl-lead")
- assert html =~ ~s(id="fl-other")
(2 assertions)

### test "the panel closes again"
- live; dismiss_tour; click `button.lc-bubble` (open).
- refute `view |> element("button.lc-bubble") |> render_click() =~ ~s(class="lc-panel")`  (clicking the bubble a second time closes the panel; the bubble is still present when open)
(1 assertion)

### describe "the strip is styled at the width it is visible at"
Comment above: "The bug this guards: `.fl-strip { display: none }` lives inside `@media (max-width: 1100px)`, and so did every rule that styled the strip's head and its button. Dead where they sat, missing where the strip is actually shown -- so the button rendered at 16px with no background and read as a stray line of prose rather than a control. A LiveView test cannot catch that, because the markup was always right. This can."

Describe setup (after outer setup, which still runs):
```
%{css: always_applies(File.read!(Path.join(File.cwd!(), "assets/css/app.css")))}
```
Helper (private, defined after tests), comment: "The stylesheet with every `@media` block removed: only the rules that apply at any width. The pattern assumes rules nest one level deep inside a media block, which is how this file is written. The assertion is there so that if that ever stops being true, this fails loudly instead of quietly returning text in which everything looks fine."
```
defp always_applies(css) do
  stripped = Regex.replace(~r/@media[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/, css, "")
  assert stripped =~ ~r/^\.fl-strip\s*\{/m, "media-block stripping did not work"
  refute stripped =~ ~r/^\s+\.fl-sheet\s*\{/m, "media-block stripping left phone rules in"
  stripped
end
```
(2 assertions inside the helper, executed once per test in this describe: after removing all single-nesting `@media` blocks, a top-level `.fl-strip {` rule must remain at column 0, and no indented `.fl-sheet {` rule may remain)

#### test "its head and button are not stranded in the phone's media query"
- for {name, pattern} in [{".fl-strip-head", ~r/^\.fl-strip-head\s*\{/m}, {".fl-strip .ask", ~r/^\.fl-strip \.ask\s*\{/m}]: assert css =~ pattern, "#{name} is only defined inside a max-width media query, where .fl-strip is display:none -- so it styles nothing, and the strip renders unstyled at the width that actually shows it"
(2 executed assertions + 2 in helper = 4)

### Behavior not obvious from the code:
- The follow view (/links/:id/read) shows a one-time tour card ("fl-tour-veil") on first visit; while shown the chat bubble ("lc-bubble") is NOT rendered. "dismiss_tour" removes the veil and reveals the bubble.
- Chat UI: `button.lc-bubble` (phx-click="toggle_chat") toggles `.lc-panel`; panel has `form[phx-submit=chat_send]` with field "message"; empty chat shows `.lc-openers` buttons (including "What does the second document already answer?" and "Which connection is doing the most work?") which disappear once a message exists; clicking an opener submits it as a question.
- "cite_edge" event with %{"edge" => edge id as string} opens the panel and puts the edge's `why` text ("They part.") into the chat; the markup must not contain "cite_current".
- Markup contract for the reference strip: `.fl-mid`, `.fl-strip` with `.fl-strip-head` (containing `.rel`, `.nth`, and an "ask about this" button), `.fl-sheet`, `.far`, blocks with ids starting `blk-lead-` and `blk-other-`, attributes `data-peer-ref=` and `data-edge=` on blocks, columns `#fl-lead` and `#fl-other` always in the DOM, and exactly one `class="shut"` element.
- A failing LLM call (no network) must end with the "thinking" indicator removed; no specific error text is asserted.
- CSS contract in assets/css/app.css: top-level (non-@media) rules `.fl-strip {`, `.fl-strip-head {`, `.fl-strip .ask {` at column 0, and `.fl-sheet {` rules appear only indented (inside media). This is a stylesheet-structure test with Elixir-regex over the file text.

---

## link_flow_test.exs  (16 tests; covers starting a link from a draft at /works/:slug?view=read, and the link pages /links/:id and /links/:id/read; Marginalia.Links)

Module: MarginaliaWeb.LinkFlowTest. `use MarginaliaWeb.ConnCase, async: false`; imports Phoenix.LiveViewTest, Marginalia.AccountsFixtures; alias Marginalia.{Links, Works}.

Moduledoc: "Starting a link from a draft: who is offered, what one click does, and the page you land on while the pass is still running."

### Setup (outer; every test)
```
Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
previous = Application.get_env(:marginalia, :deepseek_api_key)
Application.put_env(:marginalia, :deepseek_api_key, nil)
on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)
user = user_fixture()
make = fn title, status ->
  body = "# #{title}\n\nA sentence long enough to be a section here.\n\n" <> String.duplicate("word ", 200)
  {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
  {:ok, w} = Works.set_status(w, status)
  w
end
%{conn: log_in_user(conn, user), user: user,
  a: make.("First draft", "read"), b: make.("Second draft", "read"),
  unread: make.("Still reading", "reading")}
```
Comments: "`link_to` starts the pass in a detached task, so that task needs the sandbox connection too -- otherwise it dies mid-update and takes the test's connection with it." and "and no key, so the pass fails immediately rather than reaching for the network: what is under test is the flow, not the model".
LLM mechanism: `:deepseek_api_key` set to nil via put_env (restored on_exit); the linking pass thus fails immediately (status goes to "failed" in the background) with no network. No fake provider. A draft's status "read" means analysed ("has a graph"); "reading" means analysis not complete. None of the works have nodes/graph here, only sections.

### test "the control offers the other drafts that have been read"
- `{:ok, view, _} = live(conn, ~p"/works/#{a.slug}?view=read")`; `html = render_click(view, "toggle_linking", %{})`
- assert html =~ "Second draft"
- comment "a draft with no graph has nothing to relate, so it is not offered"; refute html =~ "Still reading"
- comment "and neither is this one"; refute html =~ ~s(phx-value-id="#{a.id}")
(3 assertions)

### test "one click pairs them, starts the pass, and goes to the link"
- live /works/<a.slug>?view=read; `render_click(view, "toggle_linking", %{})`.
- assert `{:error, {:live_redirect, %{to: to}}} = render_click(view, "link_to", %{"id" => to_string(b.id)})`
- `link = Links.get_for(a.id, b.id)`; assert link, "the pair should have been created"
- assert to == "/links/#{link.id}?lead=#{a.slug}"
(3 assertions; redirect target: `/links/<link id>?lead=<slug of the draft you started from>`)

### test "linking the same pair twice reuses the one link"
(no conn use)
- comment "the pair is unordered, so asking from either side is the same link"
- `{:ok, one} = Links.get_or_create(a.id, b.id)`; `{:ok, two} = Links.get_or_create(b.id, a.id)`
- assert one.id == two.id
- assert length(Links.for_work(a.id)) == 1
(2 assertions)

### test "a draft belonging to someone else cannot be linked in"
- `theirs = user_fixture()`; `{:ok, other} = Works.create_work(theirs.id, %{"title" => "Not yours", "body" => String.duplicate("word ", 300)})`; `{:ok, other} = Works.set_status(other, "read")`.
- live /works/<a.slug>?view=read; toggle_linking; `html = render_click(view, "link_to", %{"id" => to_string(other.id)})` (id of a work the user does not own, sent directly although not offered)
- assert html =~ "can&#39;t be linked" or html =~ "can't be linked"
- assert Links.for_work(a.id) == []
(2 assertions; the flash/error text is "... can't be linked ..." and no link row is created)

### describe "the page you land on"
Describe setup: `{:ok, link} = Links.get_or_create(a.id, b.id)`; `%{link: link}` (link status is the default, i.e. pending/working; not set to "linked").

#### test "says it is working while the pass runs"
- `{:ok, _view, html} = live(conn, ~p"/links/#{link.id}")`
- comment "both maps and the pairs being tried between them"
- assert html =~ ~s(id="wiring")
- assert html =~ "possible pairs"
- comment "and it is honest that the arcs are attempts, not findings"
- assert html =~ "The nodes are yours."
- refute html =~ ~s(id="split")
(4 assertions)

#### test "the follow view says so too, and subscribes"
- `{:ok, view, html} = live(conn, ~p"/links/#{link.id}/read?lead=#{a.slug}")`
- assert html =~ ~s(id="wiring")
- comment "when the pass lands, the page fills in without a reload"
- `{:ok, _} = Links.set_status(link, "linked", %{summary: "They are related."})`
- `send(view.pid, {:link, :done})`  (the LiveView handles a plain message `{:link, :done}` from a PubSub subscription; the test sends it directly to the view process)
- `html = render(view)`
- refute html =~ ~s(id="wiring")
- assert html =~ ~s(id="follow")
(3 assertions)

#### test "a failure is shown with a way to retry"
- `{:ok, _} = Links.set_status(link, "failed", %{error: ":truncated"})`; `{:ok, _view, html} = live(conn, ~p"/links/#{link.id}")`
- assert html =~ "did not go through"
- assert html =~ ":truncated"
- assert html =~ "Try again"
(3 assertions)

### describe "the tour on the follow view"
Describe setup: `{:ok, link} = Links.get_or_create(a.id, b.id)`; `{:ok, link} = Links.set_status(link, "linked", %{summary: "They talk."})`; `%{link: link}`.

#### test "a first visit is told how to work the page"
- `{:ok, _view, html} = live(conn, ~p"/links/#{link.id}/read")`
- assert html =~ "Two documents, read as one"
- assert html =~ "The left is what you are reading"
(2 assertions)

#### test "it is marked seen on sight, so it does not come back"
(multi-line head `%{conn: conn, link: link, user: user}`)
- live /links/<id>/read.
- assert "follow" in Marginalia.Repo.reload!(user).seen_tours   (users have a `seen_tours` list field; mount appends "follow" immediately)
- refute render_click(view, "dismiss_tour", %{}) =~ "Two documents, read as one"
- `{:ok, _view, html} = live(conn, ~p"/links/#{link.id}/read")` (second visit)
- refute html =~ "Two documents, read as one"
(3 assertions)

#### test "the ? in the bar brings it back"
- live; dismiss_tour; 
- assert `view |> element("button.fl-help") |> render_click() =~ "Two documents, read as one"`
(1 assertion)

### describe "the split view is gone"

#### test "its module no longer exists"
- refute Code.ensure_loaded?(MarginaliaWeb.LinkLive.Show)
(1 assertion; Elixir-module-specific, no web interaction -- the equivalent is that no separate "split" page exists)

#### test "/links/:id serves the follow view, and /read still works"
- `{:ok, link} = Links.get_or_create(a.id, b.id)`; `{:ok, _} = Links.set_status(link, "linked", %{summary: "Related."})`
- for path <- ["/links/#{link.id}", "/links/#{link.id}/read"]: `{:ok, _view, html} = live(conn, path)`; assert html =~ ~s(id="follow"), "#{path} did not render the follow view"; refute html =~ ~s(id="split")
(4 executed assertions)

#### test "nothing offers a Split tab any more"
- linked pair as above ("Related."); `{:ok, _view, html} = live(conn, ~p"/links/#{link.id}")`
- refute html =~ ">Split<"
(1 assertion)

### describe "one draft, several references"
Describe setup (receives conn, a, b, user from outer):
```
{:ok, c} = Works.create_work(user.id, %{"title" => "Third draft",
  "body" => "# Third\n\nA sentence that is long enough.\n\n" <> String.duplicate("word ", 200)})
{:ok, c} = Works.set_status(c, "read")
{:ok, one} = Links.get_or_create(a.id, b.id)
{:ok, one} = Links.set_status(one, "linked", %{summary: "B answers A."})
{:ok, two} = Links.get_or_create(a.id, c.id)
{:ok, two} = Links.set_status(two, "linked", %{summary: "C develops A."})
%{conn: conn, a: a, b: b, c: c, one: one, two: two}
```

#### test "the draft lists every one of them"
- `{:ok, _view, html} = live(conn, ~p"/works/#{a.slug}?view=read")`
- assert html =~ "read alongside"
- assert html =~ "Second draft"
- assert html =~ "Third draft"
(3 assertions)

#### test "the reference can be swapped without leaving the page"
- `{:ok, view, html} = live(conn, ~p"/links/#{one.id}?lead=#{a.slug}")`
- comment "the other one is offered"; assert html =~ "Third draft"
- comment: "and patching to it actually swaps the pair. `@link` was only set in mount, so a patch to another :id would have kept the old pair and shown the wrong document under the right title."
- assert html =~ ~s(<span class="t">Second draft</span>)
- `html = render_patch(view, ~p"/links/#{two.id}?lead=#{a.slug}")`
- assert html =~ ~s(<span class="t">Third draft</span>)
- comment "the account of the relationship swapped with it"
- assert html =~ "C develops A."
- refute html =~ "B answers A."
(6 assertions; live navigation by patch (same LiveView, params change) must reload link, reference title and summary)

#### test "a draft with one link gets no switcher"
- `{:ok, _view, html} = live(conn, ~p"/links/#{one.id}?lead=#{b.slug}")` (b has only the one link)
- refute html =~ "fl-pick"
(1 assertion)

### Behavior not obvious from the code:
- Offered drafts in the link picker: only the user's own other works with status "read"; works in "reading" are excluded, and the current draft is excluded (no `phx-value-id="<a.id>"`).
- "link_to" with an id not owned by the user does not link and shows "can't be linked" (possibly HTML-escaped); `Links.for_work(a.id)` stays `[]`.
- "link_to" success: creates (or reuses) the link, starts the pass in a detached task, and live-redirects to `/links/<id>?lead=<a.slug>`.
- `Links.get_or_create/2` is symmetric (unordered pair); `Links.for_work/1` lists links regardless of side; `Links.get_for/2` finds a link by the two work ids; `Links.set_status(link, status, attrs)` with attrs `summary`/`error`.
- Link pages: while status is not "linked"/"failed" show `#wiring` ("possible pairs", "The nodes are yours."); "failed" shows "did not go through", the raw error text (e.g. ":truncated") and "Try again"; "linked" shows `#follow`. Both /links/:id and /links/:id/read render the follow view; there is no `#split` and no ">Split<" tab.
- The follow view subscribes to link updates; a `{:link, :done}` message re-reads the link and swaps wiring for follow.
- Tour: first visit shows "Two documents, read as one" / "The left is what you are reading"; mount marks tour "follow" in `user.seen_tours`; "dismiss_tour" hides it; `button.fl-help` re-shows it.
- A draft with 2+ links lists them ("read alongside", titles) and lets the reference be switched via patch; with one link there is no switcher (class `fl-pick`); header shows `<span class="t">TITLE</span>` for the reference draft.


---

TOTALS (assert/refute lines in source by grep; for-loop assertions count once per source line, helper asserts included; some lines mention assert in message text so counts are within a few):

| file | tests | assertion lines |
|---|---|---|
| import_flow_test.exs | 25 | 61 |
| inline_thread_test.exs | 9 | 23 |
| landing_features_test.exs | 34 | 69 |
| landing_live_test.exs | 14 | 40 |
| link_chat_flow_test.exs | 15 | 40 |
| link_flow_test.exs | 16 | 39 |

TOTALS: tests=113 assertions=272

# PART 7. Web, link index/public pages/reading/rewrite panel

# D3: LiveView tests, grouped by page/route

Common facts for every file below (from test/support/conn_case.ex and accounts_fixtures.ex):

- `use MarginaliaWeb.ConnCase`: `setup` yields `conn: build_conn()` (unauthenticated). `log_in_user(conn, user)` generates a session token and puts `:user_token` in the session. `user_fixture(attrs)` registers a user with `email: "user<unique_int>@example.com"`, `password: "hello world!"`; passing `%{email: ...}` overrides the email.
- "owner" in these tests = `user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})`. `owner_email` comes from `config/runtime.exs`: `System.get_env("OWNER_EMAIL", "bobbbygrayson@gmail.com")`. The public pages (/drafts, /linked, /reading publish) are scoped to this account.
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})` is used in most setups so LiveView processes and spawned tasks share the test's DB connection.
- No fixtures exist for works, folders, sections, links; every test builds data inline through `Works.create_work/2`, `Works.set_status/2`, `Works.insert_node/1`, `Links.get_or_create/2`, `Repo.insert!` etc. Exactly how is recorded per test.
- LLM mechanism in this group: NO FakeHub, no stub provider. Three files (read_view_test, rewrite_apply_test, rewrite_panel_test) do `Application.put_env(:marginalia, :deepseek_api_key, "test-key")` only so the chat composer / rewrite panel render (a key must be configured for those UI parts to show); with config/test.exs endpoints at http://127.0.0.1:1 no model answer ever returns. link_index_test does the opposite: sets `:deepseek_api_key` to `nil`. All restore the previous value in `on_exit`. No test in this group makes a model call succeed; the rewrite-panel tests rely on the panel rendering before any answer arrives.
- Route map (from lib/marginalia_web/router.ex): `/links` LinkLive.Index; `/links/:id` LinkLive.Read (:show); `/linked` LinkedLive.Index; `/linked/:id` LinkedLive.Show; `/drafts` DraftLive.Index; `/drafts/:slug` DraftLive.Show; `/drafts/:slug/changes` DraftLive.Changes; `/reading` ReadingLive.Index; `/reading/:slug` ReadingLive.Story; `/reading/:slug/:ordinal` ReadingLive.Step; `/works/:id` WorkLive.Show (tests pass the work's slug as :id). `/links*` and `/works/*` need login; `/linked`, `/drafts`, `/reading` are public.

Section order below: /links (3 files), /linked (2), /drafts (2), /reading (2), /works/:slug (8 files incl. one pure-function test of WorkLive.Show.piles/1). 99 tests in total across 17 files.

======================================================================
# ROUTE GROUP: /links and /links/:id (logged-in owner of the drafts)
======================================================================

## test/marginalia_web/live/link_index_test.exs  (7 tests; covers MarginaliaWeb.LinkLive.Index at /links)

Module doc: "The page that lists every linked pair and makes new ones." `async: false`.

Setup (applies to every test), `setup %{conn: conn}`:
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`.
- `previous = Application.get_env(:marginalia, :deepseek_api_key)`; `Application.put_env(:marginalia, :deepseek_api_key, nil)`; `on_exit` restores `previous`.
- `user = user_fixture()` (an ordinary user, not the owner).
- Local fun `make.(title, status)`: body = `"# #{title}\n\nA sentence long enough to be its own section.\n\n" <> String.duplicate("word ", 200)`; `{:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})`; `{:ok, w} = Works.set_status(w, status)`; returns w.
- Context returned: `conn: log_in_user(conn, user)`, `user`, `a: make.("Alpha draft", "read")`, `b: make.("Beta draft", "read")`, `unread: make.("Gamma draft", "reading")`.

### test "it offers the drafts that have been read, and says why not the others"
- `{:ok, _view, html} = live(conn, "/links")`
- assert html =~ "Alpha draft"
- assert html =~ "Beta draft"
- refute html =~ "Gamma draft"   (status "reading" draft not offered)
- assert html =~ "still being read"   (the page explains why others are absent)
- 4 assertions.

### test "picking two and linking them starts the pass and goes to the pair"
- `{:ok, view, _} = live(conn, "/links")`
- comment: "one form, both selects, as the browser submits it"
- `render_change(view, "pick", %{"a" => to_string(a.id), "b" => to_string(b.id)})` (return value unused)
- `assert {:error, {:live_redirect, %{to: to}}} = render_submit(view, "make", %{"a" => to_string(a.id), "b" => to_string(b.id)})`
- `link = Links.get_for(a.id, b.id)` (work ids); `assert link` (truthy: a Link row exists after the submit)
- assert to == "/links/#{link.id}"
- 3 assertions. Event names: "pick" (phx-change) and "make" (phx-submit); params keyed "a" and "b", ids as strings.

### test "the same draft twice is refused"
- live /links; `render_change(view, "pick", %{"a" => to_string(a.id), "b" => to_string(a.id)})`
- `html = render_submit(view, "make", %{"a" => to_string(a.id), "b" => to_string(a.id)})`
- assert html =~ "two different drafts"
- assert Links.for_user(a.user_id) == []   (no link created; `Links.for_user/1` takes a user id and returns a list)
- 2 assertions.

### test "existing pairs are listed with what was found"
- `{:ok, link} = Links.get_or_create(a.id, b.id)`
- `{:ok, _} = Links.set_status(link, "linked", %{summary: "Beta answers Alpha."})`   (set_status/3 with attrs map)
- live /links
- assert html =~ "Alpha draft"
- assert html =~ "Beta answers Alpha."
- assert html =~ "1 linked"
- 3 assertions.

### test "a pair still being worked on says so"
- `{:ok, link} = Links.get_or_create(a.id, b.id)`; `{:ok, _} = Links.set_status(link, "linking")`   (set_status/2)
- live /links; assert html =~ "linking"
- 1 assertion.

### test "someone else's links are not listed"
- `theirs = user_fixture()`; two works for them via `Works.create_work(theirs.id, %{"title" => "Theirs one", "body" => String.duplicate("word ", 300)})` and `"Theirs two"` with the same body (no status set).
- `{:ok, _} = Links.get_or_create(x.id, y.id)`; `{:ok, mine} = Links.get_or_create(a.id, b.id)`
- live /links
- refute html =~ "Theirs one"
- assert html =~ "Alpha draft"
- assert length(Links.for_user(a.user_id)) == 1
- assert hd(Links.for_user(a.user_id)).id == mine.id
- 4 assertions.

### test "changing a pick patches the form instead of growing another one"
- comment (regression): "it was two forms, one per select, neither with an id — so every change appended a fresh copy and the row filled up with dead dropdowns"
- helper `count(html, needle) = length(String.split(html, needle)) - 1` (occurrences of substring).
- `{:ok, view, html} = live(conn, "/links")`; assert count(html, "<select") == 2
- `html = render_change(view, "pick", %{"a" => to_string(a.id), "b" => ""})`; assert count(html, "<select") == 2
- `html = render_change(view, "pick", %{"a" => "", "b" => to_string(a.id)})`; assert count(html, "<select") == 2
- Exactly two `<select` substrings anywhere in the page HTML (so no other select elements on /links in this state), initially and after each pick. 3 assertions. Empty string "" is a valid pick value.

Behavior not obvious from the code:
- Only drafts with status "read" are selectable; a "reading" draft is hidden by title but the page says "still being read".
- "make" with a == b gives an inline message containing "two different drafts" and creates no link.
- A successful "make" is a `live_redirect` (push_navigate) to `/links/<link id>`; `Links.get_for(a.id, b.id)` must find the link for the pair.
- Index shows "1 linked" (count of links in status "linked"), the link's summary text, and the word "linking" for in-progress links.
- Links are per-user: `Links.for_user(user_id)` excludes others' links.
- Total assertions in file: 20.

## test/marginalia_web/live/links_index_scroll_test.exs  (6 tests; covers MarginaliaWeb.LinkLive.Index paging and filter at /links)

Module doc: "/links with a real number of links on it. The page holds two tools and a diagram per cluster before it reaches the list it is named for, and then draws every pair. With four hundred pairs that is not a list, it is a wall — and the list starts below the fold before a single row is drawn." `async: false`. Module attribute `@page 40`.

Setup `setup %{conn: conn}`:
- Sandbox shared mode.
- `user = user_fixture()`; `body = "# H\n\n" <> String.duplicate("word ", 90)`.
- `works`: for i <- 1..24: `Works.create_work(user.id, %{"title" => "Draft #{i}", "body" => body})` then `Works.set_status(w, "read")`.
- `links`: comment "pairs, chained, so there are more than a page of them". For `{a, b} <- Enum.zip(works, tl(works)) ++ Enum.zip(works, Enum.drop(works, 2))` (23 adjacent pairs + 22 skip-one pairs = 45 pairs): `{:ok, l} = Links.get_or_create(a.id, b.id)`; `Repo.update!(Ecto.Changeset.change(l, status: "linked"))`.
- Context: conn logged in, user, works, links. No edges/nodes exist; links are "linked" with no summary.

### test "it draws a page of rows, not all of them"
- assert length(ctx.links) > @page   (45 > 40; precondition)
- live /links; `rows = length(Regex.scan(~r/class="lx-row"/, html))`
- assert rows == 40, message "#{rows} rows drawn of #{length(ctx.links)}"
- assert html =~ "Show 40 more" or html =~ "more"
- 3 assertions. Each row has an element with exactly `class="lx-row"` (attribute value exactly lx-row).

### test "asking for more gives more, and eventually all of them"
- live /links; `html = render_click(view, "more", %{})` (event "more", no params)
- assert count of `class="lx-row"` == min(@page * 2, length(ctx.links))   (= 45)
- `for _ <- 1..10, do: render_click(view, "more", %{})` (extra clicks after exhausted must not crash); `html = render(view)`
- assert count of `class="lx-row"` == length(ctx.links)   (45)
- refute html =~ "lx-more"   (show-more control gone once everything is drawn; "lx-more" must not occur anywhere in the HTML)
- 3 assertions.

### test "the filter matches either side of a pair"
- live /links; `html = render_change(view, "filter", %{"q" => "Draft 7"})`
- comment: "Draft 7 is in pairs on both sides of the ↔"
- rows = count of `class="lx-row"`; assert rows > 0; assert rows < length(ctx.links); assert html =~ "Draft 7"
- 3 assertions.

### test "a filter that matches nothing says so instead of showing everything"
- `render_change(view, "filter", %{"q" => "nonesuch"})`
- assert html =~ "Nothing matches"
- assert count of `class="lx-row"` == 0
- 2 assertions.

### test "filtering resets the paging, so the count is not a lie"
- live /links; `render_click(view, "more", %{})`; `html = render_change(view, "filter", %{"q" => "Draft 1"})`
- shown = rows; assert shown <= 40, "a narrowed list should start at one page again"
- 1 assertion.

### test "the tools and the diagrams are folded, not gone"
- live /links
- assert html =~ "<details"
- assert html =~ "relate a whole folder" or html =~ "relate two drafts"
- assert html =~ ~r/\d+ webs? of three or more/
- 3 assertions.

Behavior not obvious from the code:
- Page size is 40; each "more" adds another 40 (capped at total); the filter event resets to one page.
- With 24 works chained into one connected component, the regex `\d+ webs? of three or more` must match some summary text (probably "1 web of three or more").
- Filter param "q", event "filter" (phx-change); no-results text "Nothing matches".
- Total assertions in file: 15.

## test/marginalia_web/live/link_tag_menu_test.exs  (4 tests; covers MarginaliaWeb.LinkLive.Read at /links/:id)

Module doc (load-bearing): "The "3 links" chip, and the two links it used to hide. A hub paragraph can be the near end of several edges. The strip between the columns, the wire and the tap handler all read `block.querySelector("[data-peer-ref]")` — the *first* note on the paragraph — so the chip counted three connections and there was no way to reach the second or the third. The count was honest and the page was a dead end. What is asserted here is the markup the hover menu is built from: one entry per edge, each carrying the paragraph on the other side that it points at. The hover itself is CSS and the jump is the hook; neither is reachable from a LiveView test, and both are worthless if the entries are not on the page to begin with." `async: false`.

Module attribute `@far`:
```
"The kettle went cold on the counter."
"Nobody moved to fill it again."
"The window stayed open all night."
```

Setup `setup %{conn: conn}`:
- Sandbox shared mode. `user = user_fixture()`. `pad = String.duplicate("word ", 60)`.
- Work a: title "The novel", body `"# A\n\nHe stops in the doorway and does not go through. " <> pad` (comment: one paragraph, so all three of the near ends land on the same block).
- Work b: title "The story", body `"# B\n\n" <> Enum.map_join(@far, "\n\n", &(&1 <> " " <> pad))` (three paragraphs; comment: three, so each far end has a paragraph of its own to be snapped to).
- `Works.set_status(a, "read")`, `Works.set_status(b, "read")`.
- Local `node.(w, title, quote)`: `Works.insert_node(%{work_id: w.id, section_id: hd(Works.list_sections(w.id)).id, node_type: "beat", title: title, body: "b", quote: quote})`.
- `{:ok, link} = Links.get_or_create(a.id, b.id)`.
- `~w(pays_off tension echoes) |> Enum.zip(@far) |> Enum.with_index(1)`: for each `{{kind, quote}, i}`: `Repo.insert!(%LinkEdge{link_id: link.id, from_id: node.(a, "Near end #{i}", "He stops in the doorway").id, to_id: node.(b, "Far end #{i}", quote).id, edge_type: kind, rationale: "Reason number #{i}, which the menu has room for."})`. So: 1 pays_off -> "The kettle went cold on the counter."; 2 tension -> "Nobody moved to fill it again."; 3 echoes -> "The window stayed open all night."
- Comment: "the split view is only rendered once the pass has finished; before that the page is the waiting screen and has no paragraphs at all". Then `link = Repo.update!(Ecto.Changeset.change(link, status: "linked"))`.
- Context: logged-in conn, link.
- Helper `read(conn, link)`: `live(conn, "/links/#{link.id}")`, returns html.

### test "the chip still counts them"
- assert read(conn, link) =~ "3 links"   (1 assertion)

### test "one entry per edge, not one for the first"
- `for i <- 1..3`: assert html =~ "Far end #{i}", message "the menu should name every far end, including ##{i}"; assert html =~ "Reason number #{i}", message "and give its reason"
- comment "the left column's chip: three buttons under the one paragraph"; assert length(Regex.scan(~r/class="fl-jump/, html)) >= 3
- 3 assertion statements (2 in the loop, run 3x each, plus 1).

### test "each entry carries the paragraph it snaps to"
- `refs = Regex.scan(~r/data-peer-ref="([^"]+)"/, html) |> Enum.map(fn [_, ref] -> ref end) |> Enum.uniq()`
- comment: "three far ends in three different paragraphs of the other draft; if the peer refs collapsed to one, the jumps would all land in the same place and the menu would be decoration"
- assert Enum.sort(refs) == ["s1p1", "s1p2", "s1p3"]   (the unique `data-peer-ref` values on the whole page equal exactly these three; ref format `s<section>p<paragraph>`, 1-based)
- 1 assertion.

### test "the relation of each entry is its own, not the paragraph's"
- `for kind <- ~w(pays_off tension echoes)`: assert html =~ "fl-jump k-#{kind}", message "entry for #{kind} should be coloured as itself"
- comment "and the chip over a paragraph whose edges disagree says so rather than borrowing the colour of the first one"; assert html =~ "fl-tagwrap mixed"
- 2 assertion statements.

Behavior not obvious from the code:
- Exact class strings: `fl-jump k-<edge_type>` (adjacent, one space), `fl-tagwrap mixed` when a paragraph's edges differ in type, `class="fl-jump` prefix on the buttons, attribute `data-peer-ref="s1pN"`.
- The left paragraph hosts three edges so the chip text is "3 links"; the right-hand targets are paragraphs 1-3 of draft b's first section.
- Total assertions in file: 7.

======================================================================
# ROUTE GROUP: /linked and /linked/:id (public)
======================================================================

## test/marginalia_web/live/linked_index_test.exs  (5 tests; covers Marginalia.Links.public_links/0 and MarginaliaWeb.LinkedLive.Index at /linked)

Module doc: "392 pairs is more list than anyone scrolls. What is tested is the ordering and the narrowing, because both decide what a visitor sees in the first screenful — and the query count, because the first version asked for an edge count per link." `async: false`.

Setup `setup do` (tests destructure `%{conn: conn}` themselves; conn is unauthenticated):
- Sandbox shared mode. `owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})`.
- `body = "# H\n\n" <> String.duplicate("word ", 300)`.
- `work.(title)`: create_work(owner.id, %{"title" => title, "body" => body}) then set_status "read".
- `node.(w)`: `Works.insert_node(%{work_id: w.id, section_id: hd(Works.list_sections(w.id)).id, node_type: "beat", title: "a beat", body: "b", quote: "word word"})`.
- `pair.(a, b, kinds)`: `Links.get_or_create(a.id, b.id)`; for each kind k `Repo.insert!(%LinkEdge{link_id: l.id, from_id: node.(a).id, to_id: node.(b).id, edge_type: k})` (fresh nodes per edge, no rationale). Link status left at default.
- Works: "Quiet one", "Quiet two", "Argues one", "Argues two".
- `pair.(quiet_a, quiet_b, ~w(develops develops develops pays_off))` (comment: more edges, but no tension); `pair.(loud_a, loud_b, ~w(tension develops))` (comment: fewer edges, but they disagree).
- Returns `%{owner: owner}`.

### test "a pair with a tension outranks a pair with more edges"
- `[first | _] = Links.public_links()` (arity 0)
- assert first.tensions == 1
- assert first.edges == 2, "fewer edges, and still first: the tension is the finding"
- 2 assertions. Rows expose integer fields `tensions` and `edges`.

### test "the page says how many of them contain one"
- `{:ok, _view, html} = live(conn, "/linked")`
- assert html =~ "2 pairs"
- assert html =~ "1 of them contain a tension"
- assert html =~ "1 tension"
- 3 assertions.

### test "the filter narrows by either title"
- live /linked; `html = render_change(view, "filter", %{"q" => "Argues"})`
- assert html =~ "Argues one"; refute html =~ "Quiet one"
- 2 assertions.

### test "a filter matching nothing says so rather than showing an empty list"
- `render_change(view, "filter", %{"q" => "nothing here"})`; assert html =~ "Nothing matches"
- 1 assertion.

### test "counting the edges does not cost a query per link"
- comment "the shape that matters: one call, not one per pair"
- `{micros, rows} = :timer.tc(&Links.public_links/0)`
- assert length(rows) == 2
- assert micros < 500_000, "public_links/0 took #{div(micros, 1000)}ms for two pairs"
- 2 assertions (wall-clock bound 500 ms; guards against N+1).

Behavior not obvious from the code:
- Ranking: pairs with tension edges sort before pairs with more edges.
- Page summary strings: "2 pairs", "1 of them contain a tension", per-row "1 tension".
- Filter matches either draft's title; param "q", event "filter".
- Total assertions in file: 10.

## test/marginalia_web/live/public_linked_test.exs  (5 tests; covers LinkedLive.Index and LinkedLive.Show at /linked and /linked/:id, Links.public_link/1)

Module doc: "Pairs of drafts, and what runs between them, read by a stranger. The scoping tests are the ones that matter: this reads two drafts at once, so getting the owner check wrong exposes two people's work rather than one." `async: false`.

Setup `setup do`:
- Sandbox shared mode; owner (owner_email), stranger = user_fixture().
- `body = "# H\n\n" <> String.duplicate("word ", 300)`; `make.(user, title)`: create_work + set_status "read".
- Works: a = owner "The novel"; b = owner "The story"; theirs_a = stranger "Their first"; theirs_b = stranger "Their second".
- `node.(w, title)`: insert_node `%{work_id, section_id: hd(Works.list_sections(w.id)).id, node_type: "beat", title: title, body: "b", quote: "word word word"}`.
- `{:ok, link} = Links.get_or_create(a.id, b.id)` with edge `%LinkEdge{link_id: link.id, from_id: node.(a, "He stops in the doorway").id, to_id: node.(b, "The unanswered question").id, edge_type: "pays_off", rationale: "Nine pays off the promise the story made."}`.
- `{:ok, theirs} = Links.get_or_create(theirs_a.id, theirs_b.id)` with edge from `node.(theirs_a, "Private")` to `node.(theirs_b, "Also private")`, `edge_type: "develops"`.
- `{:ok, empty} = Links.get_or_create(b.id, make.(owner, "Unrelated").id)` (owner pair with no edges).
- Returns `%{link: link, theirs: theirs, empty: empty}`. No link status updates.

### test "a stranger sees the pair and its edges"
- `live(build_conn(), "/linked/#{ctx.link.id}")`
- assert html =~ "The novel"; "The story"; "He stops in the doorway"; "pays off" (edge type with underscore shown as space); "Nine pays off the promise the story made."
- 5 assertions.

### test "somebody else's pair is not readable"
- assert {:error, {:live_redirect, %{to: "/linked"}}} = live(build_conn(), "/linked/#{ctx.theirs.id}")
- assert Links.public_link(ctx.theirs.id) == nil
- 2 assertions.

### test "a pair that found nothing is not offered"
- assert Links.public_link(ctx.empty.id) == nil
- live(build_conn(), "/linked"); refute html =~ "Unrelated"
- 2 assertions.

### test "the index lists the owner's pairs only"
- live /linked (unauthenticated)
- assert html =~ "The novel"; refute html =~ "Their first"; assert html =~ "1 edges" or html =~ "1 edge"; assert ctx.link.id
- 4 assertions.

### test "it carries no control that writes"
- live /linked/<link id>; `for control <- ~w(make pick relink edit_block suggest_rewrite)`: refute html =~ ~s(phx-click="#{control}")
- 1 assertion statement (5 executed). Exact strings like `phx-click="make"` must not occur.

Behavior not obvious from the code:
- `Links.public_link/1` (by link id) returns nil for a pair owned by a non-owner and for a pair with zero edges.
- Total assertions in file: 14.

======================================================================
# ROUTE GROUP: /drafts, /drafts/:slug, /drafts/:slug/changes (public)
======================================================================

## test/marginalia_web/live/public_drafts_test.exs  (7 tests; covers DraftLive.Index and DraftLive.Show at /drafts and /drafts/:slug, Works.public_draft/1)

Module doc: "The owner's drafts, out in the open. The interesting tests are the ones about everybody else. A visitor who uploads something has always had exactly one thing — a private link — and a public index of the owner's work must not quietly become an index of theirs." `async: false`.

Setup `setup do`: sandbox shared; owner (owner_email) and stranger; `body = "# One\n\n" <> String.duplicate("word ", 300)`; `mine = Works.create_work(owner.id, %{"title" => "A draft of my own", "body" => body})`; `theirs = Works.create_work(stranger.id, %{"title" => "Somebody else's", "body" => body})`. No set_status. Returns owner, stranger, mine, theirs.

### test "a stranger with no account sees the owner's drafts listed"
- `live(build_conn(), "/drafts")`
- assert html =~ "A draft of my own"
- assert html =~ "#{ctx.mine.word_count} words"   (work struct field `word_count`, rendered as "<n> words")
- 2 assertions.

### test "somebody else's draft is not on the list"
- live /drafts; refute html =~ "Somebody else's"   (1)

### test "somebody else's draft is not served by slug either"
- assert {:error, {:live_redirect, %{to: "/drafts"}}} = live(build_conn(), "/drafts/#{ctx.theirs.slug}")
- assert Works.public_draft(ctx.theirs.slug) == nil
- 2 assertions.

### test "the owner's draft reads, with no account, and is indexable"
- live /drafts/<mine.slug>
- assert html =~ "A draft of my own"
- assert html =~ "index, follow"
- refute html =~ "noindex"
- 3 assertions (robots meta content "index, follow"; "noindex" must not appear anywhere).

### test "the public page carries none of the controls that write or spend"
- live /drafts/<mine.slug>; `for control <- ~w(summarise_document summarise suggest_rewrite edit_block save_block start_read)`: refute html =~ control, "#{control} is reachable from the public draft page"
- 1 assertion statement (6 executed). Plain substring check: these words appear nowhere in the page HTML.

### test "reading one mints no account for the visitor"
- `before = Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count)`; live /drafts/<mine.slug>; assert `Repo.aggregate(User, :count) == before`, message "a public page that mints a user row per crawler fills the users table"
- 1 assertion.

### test "a slug nobody owns goes back to the list rather than erroring"
- assert {:error, {:live_redirect, %{to: "/drafts"}}} = live(build_conn(), "/drafts/not-a-real-slug")   (1)

Behavior not obvious from the code:
- Unknown slug and non-owner slug behave identically: live_redirect to /drafts; no flash asserted.
- `Works.public_draft(slug)` returns nil (not an error tuple) for a non-owner's or nonexistent work.
- Total assertions in file: 11.

## test/marginalia_web/live/public_changes_test.exs  (6 tests; covers DraftLive.Changes at /drafts/:slug/changes and the link on DraftLive.Show)

Module doc: "The diff, readable by a stranger. "Every change is kept" was the one claim on the front page nobody could check: the before and after lived behind a login, which makes it a promise rather than a demonstration." `async: false`.

Setup `setup do`:
- sandbox shared; owner (owner_email), stranger.
- `body = "# One\n\nALPHA the first paragraph. " <> String.duplicate("word ", 150) <> "\n\nBRAVO the second. " <> String.duplicate("word ", 150)`.
- `mine` = create_work(owner.id, %{"title" => "Mine", "body" => body}); `theirs` = create_work(stranger.id, %{"title" => "Theirs", "body" => body}).
- `section = hd(Works.list_sections(mine.id))`; `block = section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))`.
- `{:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"), origin: "rewrite", note: "cuts the gloss")`   (replace_block/4: section, old block text, new block text, keyword opts).
- Returns `%{mine: Repo.reload!(mine), theirs: theirs}`.

### test "a stranger sees what the draft used to say"
- live(build_conn(), "/drafts/#{ctx.mine.slug}/changes")
- assert html =~ "As it arrived"
- assert html =~ "ALPHA", "the version that was replaced"
- assert html =~ "AMENDED"
- assert html =~ "1 edited"
- 4 assertions.

### test "and where the change came from"
- same page; assert html =~ "rewrite"; assert html =~ "cuts the gloss"   (2)

### test "the draft page links to it once there is something to show"
- live(build_conn(), "/drafts/#{ctx.mine.slug}")
- assert html =~ "1 change since it arrived"
- assert html =~ "/drafts/#{ctx.mine.slug}/changes"
- 2 assertions.

### test "somebody else's draft has no public diff either"
- assert {:error, {:live_redirect, %{to: "/drafts"}}} = live(build_conn(), "/drafts/#{ctx.theirs.slug}/changes")   (1)

### test "an unchanged draft says so instead of showing an empty table"
- `{:ok, other} = Works.create_work(Marginalia.Accounts.owner().id, %{"title" => "Untouched", "body" => "# H\n\n" <> String.duplicate("word ", 300)})`   (`Accounts.owner/0` returns the user with owner_email, created in setup)
- live(build_conn(), "/drafts/#{other.slug}/changes")
- assert html =~ "Nothing has been changed yet"
- refute html =~ "As it arrived"
- 2 assertions.

### test "it carries no control that writes"
- live changes page of mine; `for control <- ~w(edit_block save_block suggest_rewrite apply_rewrite summarise)`: refute html =~ control   (1 statement, 5 executed)

Behavior not obvious from the code:
- After one replace_block, the draft page shows "1 change since it arrived" (singular) and a link to `/drafts/<slug>/changes`; the changes page shows "1 edited" under a section headed "As it arrived", with both the replaced text (ALPHA) and the new text (AMENDED), the origin "rewrite" and the note "cuts the gloss".
- Total assertions in file: 12.

======================================================================
# ROUTE GROUP: /reading, /reading/:slug, /reading/:slug/:ordinal
======================================================================

## test/marginalia_web/live/public_reading_test.exs  (13 tests; covers ReadingLive.Index/Story/Step, Marginalia.Folders publish/unpublish/rename_folder/published, Stacks.Step and Stacks.Story)

Module doc: "A published stack, and everything that must stay unpublished. The writer whose account can publish also keeps contracts and employment agreements in folders beside the one being published. So the interesting tests here are the negative ones: private by default, one folder at a time, and nothing readable off a guessed id." `async: false`.

Top-level setup `setup do`:
- sandbox shared; `owner` (owner_email).
- `{:ok, folder} = Folders.create_folder(owner.id, %{"name" => "A Backend For Something"})`; `{:ok, other} = Folders.create_folder(owner.id, %{"name" => "Employment agreements"})`.
- `work` = create_work(owner.id, %{"title" => "1. The first thing", "body" => "# One\n\n" <> String.duplicate("word ", 200)}); `{:ok, _} = Folders.move_work(owner.id, work.id, folder.id)`.
- `Repo.insert!(%Step{folder_id: folder.id, work_id: work.id, ordinal: 1, capability: "The thing emits a file that runs", lesson: "Emit one module and run it before building anything clever.", pitfall: "Assuming the printed form round-trips.", pitfall_quote: "a whole Double prints as 1", excerpts: [%{"caption" => "the grammar", "text" => "out_grammar do ... end"}], requires: []})`.
- `Repo.insert!(%Story{folder_id: folder.id, title: "Half of building it is fixing the thing underneath", opening: "Nothing about this is hand-written at the level you would expect.", movements: [%{"heading" => "Get it running first", "prose" => "Do the cheap part.", "steps" => [1]}], closing: "That is the method.", uncovered: [], dropped: []})`.
- Returns `%{owner, folder, other}`. Neither folder is published yet.

### describe "before anything is published"

#### test "the index says so rather than listing a private folder"  (uses ConnCase `conn`, unauthenticated)
- `live(conn, "/reading")`
- assert html =~ "Nothing published yet"
- refute html =~ "Half of building it"
- 2 assertions.

#### test "a folder is private the moment it is made"
- assert is_nil(Repo.reload!(folder).published_at)
- assert is_nil(Repo.reload!(folder).slug)
- 2 assertions (slug is nil until published).

### describe "once published"
Extra setup: `{:ok, folder} = Folders.publish(owner.id, folder.id)`; context `folder` replaced by the published folder (now has `slug` and `published_at`).

#### test "a signed-out stranger can read the telling"
- live(build_conn(), "/reading/#{folder.slug}")
- assert html =~ "Half of building it is fixing the thing underneath"
- assert html =~ "Nothing about this is hand-written"
- assert html =~ "Get it running first"
- 3 assertions.

#### test "and the step behind a paragraph of it"
- live(build_conn(), "/reading/#{folder.slug}/1")
- assert html =~ "The thing emits a file that runs"
- assert html =~ "Emit one module and run it"
- assert html =~ "Assuming the printed form round-trips"
- assert html =~ "out_grammar do", "the located passage, not the model's bare quote"
- 4 assertions.

#### test "it appears on the index"
- live(conn, "/reading") (unauthenticated); assert html =~ "Half of building it is fixing the thing underneath"   (1; the index shows the Story title)

#### test "the slug is readable and survives a rename"
- assert folder.slug == "a-backend-for-something"
- `{:ok, renamed} = Folders.rename_folder(owner.id, folder.id, "Something else entirely")`   (arity 3)
- assert renamed.slug == "a-backend-for-something", "a link already sent to somebody must not break because the folder was renamed"
- 2 assertions.

#### test "publishing one folder publishes only that one"
- assert is_nil(Repo.reload!(other).published_at)
- assert Folders.published() |> Enum.map(& &1.name) == ["A Backend For Something"]   (`Folders.published/0`, folder structs)
- 2 assertions.

#### test "taking it back down makes it unreadable again"
- `{:ok, _} = Folders.unpublish(owner.id, folder.id)`
- assert {:error, {:live_redirect, %{to: "/reading"}}} = live(build_conn(), "/reading/#{folder.slug}")   (1)

#### test "the slug is kept while private, so re-publishing restores the URL"
- `{:ok, down} = Folders.unpublish(owner.id, folder.id)`; assert down.slug == folder.slug
- `{:ok, up} = Folders.publish(owner.id, folder.id)`; assert up.slug == folder.slug
- 2 assertions.

### describe "what cannot be reached"
(no extra setup; folder unpublished, `folder.slug` is nil)

#### test "an unpublished folder is not readable by slug even if one is guessed"
- assert {:error, {:live_redirect, %{to: "/reading"}}} = live(build_conn(), "/reading/a-backend-for-something")
- assert is_nil(Repo.reload!(folder).published_at)
- 2 assertions.

#### test "a stranger cannot publish somebody's folder"
- `stranger = user_fixture()`; assert {:error, _} = Folders.publish(stranger.id, folder.id); assert is_nil(Repo.reload!(folder).published_at)   (2)

#### test "not even the folder's own non-owner writer can publish it"
- `writer = user_fixture()`; `{:ok, theirs} = Folders.create_folder(writer.id, %{"name" => "Their drafts"})`
- assert {:error, :not_owner} = Folders.publish(writer.id, theirs.id)
- assert is_nil(Repo.reload!(theirs).published_at)
- refute writer.id == owner.id
- 3 assertions.

#### test "a step of an unpublished folder is not readable"
- assert {:error, {:live_redirect, %{to: "/reading"}}} = live(build_conn(), "/reading/#{folder.slug || "x"}/1")   (folder.slug is nil here, so path is "/reading/x/1")   (1)

Behavior not obvious from the code:
- Publishing is reserved to the deploy-owner account (email == owner_email): a different user publishing even a folder they own gets `{:error, :not_owner}`; a stranger publishing someone else's folder gets some `{:error, _}`.
- Slug derives from the folder name at first publish ("A Backend For Something" -> "a-backend-for-something"), persists across rename and unpublish, and is nil before first publish.
- Unpublish only clears the published state; republish restores the same slug.
- All unreadable cases are `{:error, {:live_redirect, %{to: "/reading"}}}`.
- Total assertions in file: 27.

## test/marginalia_web/live/reading_owner_test.exs  (5 tests; covers ReadingLive.Step and ReadingLive.Story owner-only links)

Module doc: "A published reading is a page anybody can open. The documents behind it are not. So the way back to them is shown to the writer and to nobody else, and that is the only thing worth testing carefully here: a draft's slug *is* the permission to read it, so printing one on a public page gives it away to everyone who ever opens that page." `async: false`. No sandbox shared-mode call.

Top-level setup `setup do`:
- comment: "publishing is reserved to the account this deploy belongs to, not to whoever happens to own the folder — see Folders.publish/2"
- owner (owner_email); `{:ok, folder} = Folders.create_folder(owner.id, %{name: "A method"})` (atom-key map here).
- work = create_work(owner.id, %{"title" => "The first chapter", "body" => "# One\n\n" <> String.duplicate("word ", 90)}); `Folders.move_work(owner.id, work.id, folder.id)`.
- `Repo.insert!(%Stacks.Step{folder_id: folder.id, work_id: work.id, ordinal: 1, capability: "read a folder forwards"})` (only these fields).
- `{:ok, folder} = Folders.publish(owner.id, folder.id)`. Returns owner, folder, work.

### describe "the step page"  (route /reading/#{folder.slug}/1)

#### test "the writer is offered the draft it was read out of"
- `conn = log_in_user(build_conn(), ctx.owner)`; live(conn, "/reading/#{ctx.folder.slug}/1")
- assert html =~ "The first chapter"
- assert html =~ ~s(href="/works/#{ctx.work.slug}?view=read")
- assert html =~ "yours to edit"
- 3 assertions.

#### test "a stranger is not, and the slug is nowhere on the page"
- unauthenticated live; refute html =~ ctx.work.slug, "the slug is the permission; it must not leak"; refute html =~ "yours to edit"   (2)

#### test "somebody else logged in is a stranger too"
- `log_in_user(build_conn(), user_fixture())`; refute html =~ ctx.work.slug   (1)

### describe "the story page"  (route /reading/#{folder.slug})
Extra setup: inserts `%Stacks.Story{folder_id: folder.id, title: "How the thing was built", opening: "It starts with one broken link.", closing: "And it ends with seven.", movements: [%{"heading" => "The first move", "prose" => "What happened.", "steps" => [1]}]}`; returns `:ok`.

#### test "the writer is offered the folder the reading was composed from"
- logged in as owner; live /reading/<slug>
- assert html =~ "Open the folder"
- assert html =~ ~s(href="/stacks/#{ctx.folder.id}")
- 2 assertions.

#### test "a stranger sees no route into the folder"
- unauthenticated; assert html =~ "How the thing was built", "the reading itself is public"; refute html =~ "Open the folder"; refute html =~ ~s(href="/stacks/#{ctx.folder.id}")   (3)

Behavior not obvious from the code:
- Owner vs stranger is decided by the session user: a logged-in non-owner counts as a stranger.
- Step page for the owner shows the work's title, a link with exactly `href="/works/<slug>?view=read"`, and the text "yours to edit"; for strangers the work slug must not appear anywhere in the HTML.
- Total assertions in file: 11.

======================================================================
# ROUTE GROUP: /works/:slug (logged-in owner; WorkLive.Show), mostly ?view=read
======================================================================

## test/marginalia_web/live/progress_test.exs  (4 tests; covers WorkLive.Show at /works/:slug while a read runs)

Module doc: "The read takes minutes across three stages, the last of which produces nothing visible until it finishes. The writer has to be able to tell working from hung, including after a page reload." `async: true` (no shared sandbox mode call).

Setup `setup %{conn: conn}`: `user = user_fixture()`; `body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)` (plain "Chapter 1" line, no `#`); `work = create_work(user.id, %{"title" => "Draft", "body" => body})`; returns logged-in conn, work, `section: hd(Works.list_sections(work.id))`.

### test "all three stages are named while reading"
- `{:ok, work} = Works.set_status(work, "reading")`; live(conn, "/works/#{work.slug}")
- assert html =~ "Reading your draft"
- assert html =~ "Sections"
- assert html =~ "The spine"
- assert html =~ "Connections"
- comment "the weave is the stage that was previously invisible"; assert html =~ "what develops, pays off, requires, or contradicts what"
- 5 assertions.

### test "a reload mid-read recovers which stage is running"
- set_status "reading"; `Works.set_section_status(s, "read")` (context `section` bound as `s`; result unchecked)
- `{:ok, _} = Works.insert_node(%{work_id: work.id, node_type: "spine", title: "The trunk"})`
- live /works/<slug>; comment "spine exists, so sections and spine are done and the weave is running"; assert render(view) =~ "1 spine"
- 1 assertion.

### test "the stage broadcast moves the view on"
- set_status "reading"; live; `send(view.pid, {:stage, :sections, :done})`; `send(view.pid, {:stage, :weave, :start})`; assert render(view) =~ "Connections"   (1). Messages go straight to the LiveView pid.

### test "a finished read shows the map, not the progress view"
- set_status "read"; live; refute html =~ "Reading your draft"   (1)

Behavior not obvious from the code:
- Status "reading" on the default (no `view` param) route shows the progress view with the three stage names and the weave description; status "read" does not.
- Stage inference after reload: an existing spine node implies sections and spine are done; the counts include "1 spine".
- Total assertions in file: 8.

## test/marginalia_web/live/live_beats_test.exs  (4 tests; covers WorkLive.Show PubSub handling at /works/:slug?view=read)

Module doc: "A note arriving in the margin while the read runs. Every broadcast the read makes used to end in a reload that rebuilt the map and not the page. The counts ticked up live and the margin stayed empty until a refresh, so a writer watching their draft being read watched nothing happen." `async: false`.

Setup `setup %{conn: conn}`: sandbox shared; user; `body = "# One\n\nShe had been standing at the window for an hour before anyone noticed. " <> String.duplicate("word ", 260)`; work "Draft", `Works.set_status(work, "reading")`; context: logged-in conn, work, `section: hd(Works.list_sections(work.id))`.

Helper `add_beat(work, section, title)`: `{:ok, _} = Works.insert_node(%{work_id: work.id, section_id: section.id, node_type: "beat", title: title, body: "What this beat is doing.", quote: "She had been standing at the window for an hour before anyone noticed."})`.

PubSub: `Phoenix.PubSub.broadcast(Marginalia.PubSub, Analysis.topic(work.id), msg)`.

### test "a beat appears without a refresh"
- live(conn, "/works/#{work.slug}?view=read"); refute html =~ "SHE STOPS AT THE WINDOW"
- add_beat(work, section, "SHE STOPS AT THE WINDOW"); broadcast `{:section, section.id, "read"}`; `html = render(view)`
- assert html =~ "SHE STOPS AT THE WINDOW", "the beat is in the database and the page was told; it has to be on screen"
- 2 assertions.

### test "the same is true for a node broadcast"
- add_beat "A LATER BEAT"; broadcast `{:nodes, section.id, 1}`; assert render(view) =~ "A LATER BEAT"   (1)

### test "a stage broadcast refreshes the page too"
- add_beat "ARRIVED ON A STAGE"; broadcast `{:stage, :spine, :done}`; assert render(view) =~ "ARRIVED ON A STAGE"   (1)

### test "a tab that is not the read view is not rebuilt for nothing"
- live(conn, "/works/#{work.slug}?view=spine"); add_beat "NOT ON THIS TAB"; broadcast `{:section, section.id, "read"}`; comment "the map behind the spine tab still updates; the page does not get rebuilt"; `assert render(view)` (truthy only; the view must still be alive; nothing asserted about the text)   (1)

Behavior not obvious from the code:
- Three broadcast shapes must each make the read view re-load notes from the DB and re-render the page (not only the map counts): `{:section, section_id, "read"}`, `{:nodes, section_id, count}`, `{:stage, stage_atom, :done}`.
- No analysis is run; the tests broadcast directly on the work's topic.
- Total assertions in file: 5.

## test/marginalia_web/live/read_view_test.exs  (7 tests; covers WorkLive.Show read view at /works/:slug?view=read)

Module doc: "The page view, and the thing it exists for: clicking a note opens the chat already holding that note and the sections it touches." `async: false` with comment "not async: the composer, and so the holding card, only render when a key is configured, and that is global config".

Setup `setup %{conn: conn}`:
- LLM seam: `previous = Application.get_env(:marginalia, :deepseek_api_key)`; `Application.put_env(:marginalia, :deepseek_api_key, "test-key")`; on_exit restores. No model request is ever made.
- user = user_fixture(); body = `"# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\n" <> "The kettle went cold on the counter, and nobody moved to fill it again.\n\n" <> String.duplicate("word ", 260)`.
- work "Draft" via create_work, set_status "read"; `s = hd(Works.list_sections(work.id))`.
- beat = insert_node `%{work_id: work.id, section_id: s.id, node_type: "beat", title: "The kettle goes cold", body: "Nothing moves and the reader feels it.", quote: "The kettle went cold on the counter"}`.
- Context: conn logged in, work, beat, section: s. (No sandbox shared-mode call.)

### test "the draft is shown with the note beside its own paragraph"
- live(conn, "/works/#{work.slug}?view=read")
- assert html =~ "The kettle went cold on the counter"
- assert html =~ "The kettle goes cold"
- comment "the anchored span is marked, and carries the id its margin note points at"
- assert html =~ ~s(id="anchor-s1p)   (prefix, e.g. id="anchor-s1p2")
- assert html =~ "The kettle went cold on the counter</mark>"   (quote wrapped in <mark>, closing tag directly after the quote text)
- 4 assertions.

### test "clicking a note opens the chat holding it — and it stays open"
- `html = render_click(view, "discuss", %{"key" => "beat:#{beat.id}"})`
- assert html =~ "holding"
- assert html =~ "The kettle goes cold"
- comment "the patch must carry chat=1, or handle_params closes it again"
- `assert_patch(view) =~ "chat=1"`   (assert_patch/1 returns the patched path; it contains "chat=1")
- assert render(view) =~ "holding"
- 4 assertions.

### test "dropping the focus leaves the chat open"
- render_click "discuss" with the beat key; `html = render_click(view, "clear_focus", %{})`
- refute html =~ "holding"
- assert html =~ "Talk about it"
- 2 assertions.

### test "it opens on everything, with no filter applied"
- live read view; comment "Everything is the tab lit on arrival"
- assert html =~ ~s(class="mg-tab on" phx-click="set_only" phx-value-only="all")   (exact attribute order and spacing)
- refute html =~ ~s(class="mg-tab on" phx-click="set_only" phx-value-only="beats")
- comment "and the margin carries both passes at once, not just the beats"
- assert html =~ "The kettle goes cold"
- assert html =~ "tension"
- 4 assertions.

### test "trimming to tensions hides the beats"
- `html = render_click(view, "set_only", %{"only" => "tensions"})`
- refute html =~ "The kettle goes cold"
- comment "the prose is still there; only the notes were trimmed"
- assert html =~ "The kettle went cold on the counter"
- 2 assertions.

### test "a bad key is ignored rather than crashing"
- assert render_click(view, "discuss", %{"key" => "beat:0"})   (truthy return; no crash; 1 assertion)

### describe "the draft while the chat drawer is open"

#### test "is marked as collapsed, which is what turns click-to-edit off"
- `{:ok, view, html} = live(conn, "/works/#{work.slug}?view=read")`; refute html =~ "mg-read mt-6 collapsed"
- comment: "with the drawer open the left column is the reference you feed the conversation from — clicking a highlight there has to reach the margin, not open an editor on top of it"
- `html = render_click(view, "toggle_chat", %{})`; assert html =~ "collapsed"
- 2 assertions.

Behavior not obvious from the code:
- Note keys have the form "<node_type>:<node id>" (e.g. "beat:12"); a nonexistent one ("beat:0") is ignored.
- The chat drawer is URL-driven: focusing a note patches to a URL containing `chat=1`.
- `set_only` values seen: "all", "beats", "tensions". Default is "all"; the word "tension" must be in the HTML at arrival even though the fixture has no tension node (so it appears at least in the tab labels).
- Total assertions in file: 19.

## test/marginalia_web/live/read_changes_test.exs  (5 tests; covers WorkLive.Show "toggle_changes" at /works/:slug?view=read)

Module doc: "Reading the draft with what changed beside it. The Changes tab answers "what is different" away from the prose. This answers it while you are reading: the rail that normally holds the notes holds the before and after instead, and the notes move under the paragraph that caused them rather than disappearing." `async: false`.

Setup `setup %{conn: conn}`: sandbox shared; user; body `"# One\n\nALPHA the first paragraph. " <> String.duplicate("word ", 150) <> "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 150)`; work "Draft", set_status "read". Context: logged-in conn, work, user.

Helper `edit(work, from, to)`: section = first section; block = first of `String.split(section.body, ~r/\n{2,}/, trim: true)` containing `from`; `{:ok, _} = Works.replace_block(section, block, String.replace(block, from, to), origin: "rewrite", note: "cuts the gloss")`.

### test "the toggle is not offered on a draft nobody has changed"
- live /works/<slug>?view=read; refute html =~ "Show what changed"   (1)

### test "it appears once something has changed"
- edit(work, "ALPHA", "AMENDED"); live; assert html =~ "Show what changed"   (1)

### test "turning it on puts the before and after in the rail"
- edit; live; `html = render_click(view, "toggle_changes", %{})`
- assert html =~ "mg-read-rail changes"
- assert html =~ "ALPHA", "the text that was replaced has to still be readable"
- assert html =~ "AMENDED"
- assert html =~ "cuts the gloss", "and where the change came from"
- 4 assertions.

### test "the notes rail is replaced, not shown twice"
- edit; live; `on = render_click(view, "toggle_changes", %{})`; `rails = Regex.scan(~r/class="mg-read-rail/, on) |> length()`; assert rails == 1, "one rail at a time: notes or changes, never both"   (1)

### test "it toggles back"
- edit; live; click "toggle_changes" twice; `back` = second result
- refute back =~ "mg-read-rail changes"
- assert back =~ "Show what changed"
- 2 assertions.

Behavior not obvious from the code:
- The "Show what changed" toggle appears only when the work has at least one recorded change (a block replacement).
- With changes on, the rail has class beginning `mg-read-rail` followed by ` changes`; exactly one element with `class="mg-read-rail` prefix exists at a time. Toggling back removes ` changes` and restores the "Show what changed" label.
- Total assertions in file: 9.

## test/marginalia_web/live/rewrite_apply_test.exs  (1 test; covers WorkLive.Show "edit_block" at /works/:slug?view=read)

Module doc: "Dropping a candidate into the draft, and refusing to when it does not fit. The reported version: three paragraphs highlighted, the panel anchored to a fourth, and "start from this" replaced that fourth paragraph wholesale with a rewrite of the other three. `seeded/3` fell through to the candidate when the block did not contain the span, which is a silent substitution of the wrong text into the wrong place." `async: false`.

Setup `setup %{conn: conn}`: LLM seam: put_env :deepseek_api_key "test-key" (on_exit restore). user; body = `"# A draft\n\n" <> "ALPHA the first paragraph. " <> String.duplicate("word ", 120) <> "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120) <> "\n\nCHARLIE the third paragraph. " <> String.duplicate("word ", 120)`; work "Draft", set_status "read". Context: logged-in conn, work, user.

Helper `refs(view)`: `Regex.scan(~r/id="block-([^"]+)"/, render(view)) |> Enum.map(fn [_, r] -> r end)`.

Comment: "The refusal itself is unit-tested on Rewrite.place/3: reaching it through the page needs a rewrite in assigns, which needs the model to answer."

### test "editing a paragraph with no rewrite open still works"
- live /works/<slug>?view=read; `[first | _] = refs(view)`; `html = render_click(view, "edit_block", %{"ref" => first})`
- assert html =~ "mg-edit"
- assert html =~ "ALPHA the first paragraph."
- 2 assertions. (First `id="block-..."` on the page is the first paragraph block, the ALPHA one.)

Behavior not obvious from the code:
- Only the no-rewrite path is exercised through the page; the `Rewrite.place/3` refusal is unit-tested elsewhere (not in this file).
- Total assertions in file: 2.

## test/marginalia_web/live/rewrite_panel_test.exs  (8 tests; covers WorkLive.Show "suggest_rewrite" panel at /works/:slug?view=read)

Module doc: "The rewrite panel actually rendering. It stopped doing so for every selection, because the panel was handed `@rewrite_span` from inside a function component that had no such assign. A `KeyError` in a LiveView render does not surface as an error — it drops the socket — so the symptom was "one paragraph does nothing" and "more than one crashes", which are the same bug wearing two faces. Nothing here reaches the model: the panel renders as soon as the event is handled, which is before any answer comes back, and that render is the thing that was broken." `async: false`.

Setup `setup %{conn: conn}`: LLM seam: put_env :deepseek_api_key "test-key" (on_exit restore). Body = `"# A draft\n\n"` + para("She had been standing at the window for an hour.") + "\n\n" + para("The kettle went cold on the counter.") + "\n\n" + para("Nobody moved to fill it again."), where `para.(lead) = lead <> " " <> String.duplicate("word ", 120)`; work "Draft"; set_status "read". Context: logged-in conn, work.

Helpers: `first_ref(view)` = first capture of `~r/id="block-([^"]+)"/` in `render(view)`; `open(view, text)` = `render_click(view, "suggest_rewrite", %{"text" => text, "ref" => first_ref(view)})` then returns `render(view)`.

### test "one paragraph opens the panel instead of dropping the socket"
- live read view; `html = open(view, String.duplicate("word ", 120))`
- assert html =~ "mg-rewrite", "the panel has to be on the page at all"
- assert html =~ "Rewrites of"
- 2 assertions.

### test "several paragraphs open it too, and it says how much"
- `span = Enum.map_join(1..4, "\n\n", fn i -> "Paragraph #{i}. " <> String.duplicate("word ", 150) end)`; `html = open(view, span)`
- assert html =~ "mg-rewrite"
- refute html =~ "Rewrites of one line", "four paragraphs is not one line, and saying so was the original report"
- assert html =~ ~r/Rewrites of \d{3,} words/   (word count of three or more digits; the span is about 4 x 152 = 608 words)
- 3 assertions.

### test "a long span shows its extent, since the rest runs off below the panel"
- `span = "THE VERY START. " <> String.duplicate("middle ", 300) <> "THE VERY END."`; open
- assert html =~ "THE VERY START"; assert html =~ "THE VERY END"; assert html =~ "mg-rw-extent"
- 3 assertions.

### test "the steer box is there and survives the panel opening"
- open with `String.duplicate("word ", 120)`
- assert html =~ "steer_rewrite"
- assert html =~ "ask for something specific"
- 2 assertions.

### test "the socket is still alive after all of it"
- `open(view, String.duplicate("word ", 400))` (result discarded); comment "a dropped socket makes this raise rather than return markup"; assert render(view) =~ "mg-read-body"   (1)

### describe "the steering box"

#### test "is a textarea that can grow, not a one-line slot"
- open (120 words); assert html =~ ~s(name="steer"); assert html =~ "<textarea", "what people write here is a sentence or three"; assert html =~ ~s(id="rw-steer")   (3)

#### test "is never disabled, because phx-update=ignore would freeze it that way"
- comment: "the panel is opened while the pass is running, which is exactly when `disabled={@working}` would be rendered true — and `ignore` means the attribute never comes back off"
- `[box] = Regex.run(~r/<textarea[^>]*id="rw-steer"[^>]*>/, html)` (the opening tag with id `rw-steer`)
- refute box =~ "disabled", "it rendered disabled on first paint and stayed that way for good"
- assert box =~ ~s(phx-update="ignore"), "or half-typed text is lost on every patch"
- 2 assertions.

#### test "the button is the thing that goes quiet during a pass"
- open; assert html =~ ~r/<button[^>]*disabled[^>]*>\s*Again/   (a disabled button whose text begins "Again" is rendered while the pass is working)   (1)

Behavior not obvious from the code:
- Event "suggest_rewrite" takes params "text" (selected span) and "ref" (block ref from `id="block-<ref>"`). The panel renders immediately in a working state (the "Again" button disabled); since the model endpoint refuses connections, no answer arrives within the test.
- Panel heading is "Rewrites of one line" for a single line and "Rewrites of <N> words" for longer spans (N >= 100 in the test).
- The steer textarea has `id="rw-steer" name="steer" phx-update="ignore"` and must never carry `disabled`.
- Total assertions in file: 17.

## test/marginalia_web/live/note_deck_test.exs  (5 tests; covers WorkLive.Show note-rail "deck" markup at /works/:slug?view=read)

Module doc: "The rail, when a section has more notes than it has room for. What is asserted is that the notes are all still on the page. The deck is a control, and a control that quietly drops the fifth note would be a much worse bug than the height it was added to fix — invisible, and only found by somebody who knew what they were looking for." `async: false` (no sandbox shared-mode call).

Setup `setup %{conn: conn}`: user; `para = "The kettle went cold on the counter. " <> String.duplicate("word ", 120)`; `body = "# A draft\n\n" <> para <> "\n\n" <> String.duplicate("other ", 120)`; work "Draft", set_status "read"; section = first section. Context: logged-in conn, work, section.

Helpers:
- `beat(section, work, kind, title, quote)`: `Works.insert_node(%{work_id: work.id, section_id: section.id, node_type: kind, title: title, body: "why #{title}", quote: quote})`; returns node.
- `links(work, from, to, type)`: `Repo.insert!(%Marginalia.Works.Edge{work_id: work.id, from_id: from.id, to_id: to.id, edge_type: type, rationale: "because #{type}"})`. Comment: "A draft's own margin notes are its beats plus the connections between them, and the connection is shown on the beat it starts from. That is the only way to get more than one kind into one place in the rail, which is the case the stacking exists for."
- `read(conn, work)`: live /works/<slug>?view=read, returns html.
All quotes are "nowhere in the text" (unanchorable), so every note stacks at the top of the rail.

### test "four notes are four plain cards, with nothing to press"
- 4 beats titled "Beat 1".."Beat 4", kind "beat". `for i <- 1..4, do: assert(html =~ "Beat #{i}")`
- refute html =~ ~r/class="mg-note-slot [a-z_]+ deck"/, "four fits; a pager on it is noise"
- refute html =~ ~s(data-step)
- 3 assertion statements.

### test "seven notes stack by kind and every one is still on the page"
- titles (exact): "Opens on the broken link", "Locates it in file mode", "Gives a verification procedure", "Prescribes the two-part edit", "Template edits are inert", "Splits seven into four and three", "Lists the deliverables"; seven beats a..g in that order (kind "beat", quote "nowhere in the text").
- comment: "three beats carry a connection each, so the pile is four kinds: the shape of the screenshot this came from". Edges: links(b -> a, "pays_off"); links(c -> a, "pays_off"); links(d -> e, "requires"); links(e -> f, "develops"). (Note the comment says three but four edges are made.) g is bound but unused (`_ = g`).
- comment "the whole point: behind a control is not the same as gone"; `for title <- titles`: assert html =~ title, "#{title} must still be in the document"
- assert html =~ ~r/class="mg-note-slot [a-z_]+ deck"/
- assert html =~ ~s(data-step="1")
- assert html =~ ~s(data-step="-1")
- comment "seven beats in one stack, and the two pays-off connections in another"; assert html =~ "1 / 7"; assert html =~ "1 / 2"
- 6 assertion statements (loop of 7 + 5).

### test "only the first card of a stack starts visible"
- 5 beats "Beat 1".."Beat 5"; html
- comment "one `on` per deck, and it is the first"; `[deck] = Regex.run(~r/<div class="cards">.*?<\/div>\s*<div class="nav">/s, html)`; `ons = Regex.scan(~r/class="[^"]*\bon\b[^"]*"/, deck)`
- assert length(ons) == 1, "exactly one card of the five is visible to start with"
- assert html =~ "1 / 5"
- 2 assertions. Structure: `<div class="cards">` ... `</div>` whitespace `<div class="nav">`; the visible card has a class containing the word `on`.

### test "a pile of one is a card, not a deck of one"
- one beat "The only note"; assert html =~ "The only note"; refute html =~ ~s(class="nav")   (2)

### test "the pile does not lie about how deep it is"
- comment: "two layers drawn under a pile of two would say three, and the pager under it says two — a stack that contradicts its own count is worse than a flat card"
- 5 beats "Beat 1".."Beat 5" = a..e; links(b -> a, "pays_off"); links(c -> a, "pays_off"); links(d -> e, "requires")
- assert html =~ ~r/class="mg-note-slot beat deck deep"/, "five beats is deep"
- refute html =~ ~r/class="mg-note-slot pays_off deck deep"/, "two pays-off is a pair, not a pile"
- assert html =~ ~r/class="mg-note-slot pays_off deck"/
- 3 assertions. Slot class format `mg-note-slot <kind> deck`, plus ` deep` only for large stacks (five beats yes; a pair of pays_off no).

Behavior not obvious from the code:
- With four or fewer notes: plain cards, no `deck` slot class, no `data-step` attribute. With more than four, notes group by kind into `deck` stacks with a pager `<div class="nav">` reading "1 / N" and buttons `data-step="1"` / `data-step="-1"`; a kind with a single note is a plain card (no nav).
- Every note's title must remain in the HTML even when its card is not visible.
- "deep" is a modifier for bigger stacks; pinned only as 5 yes, 2 no.
- Total assertions in file: 16.

## test/marginalia_web/live/note_piles_test.exs  (7 tests; PURE FUNCTION tests of MarginaliaWeb.WorkLive.Show.piles/1)

Module doc: "How many slots a pile of margin notes turns into. The case that forced this: a section whose beats could not be anchored has no paragraph for any of them to sit beside, so every one stacks at the top of the rail. Seven of those is thirteen hundred pixels of margin against three paragraphs of prose. The rule has to hold two things at once. Most paragraphs carry one or two notes and should carry no controls; a pile that fits is easier to read than a pile with a pager on it. And nothing may be dropped — a note behind a control is still reachable, a note that grouping lost is gone." `use ExUnit.Case, async: true` (no DB). `alias MarginaliaWeb.WorkLive.Show`; calls `Show.piles(notes)` (arity 1, public). Input: list of note maps; output: list of piles, each a list of note maps.

Helpers:
- `note(kind, title)` -> `%{kind: kind, title: title, key: "#{kind}:#{title}", body: "b"}`
- `kinds(piles)` -> `Enum.map(piles, fn pile -> Enum.map(pile, & &1.kind) end)`

### test "four or fewer get a slot each, with no pager on them"
- input: [note("beat","a"), note("beat","b"), note("tension","c"), note("beat","d")]
- assert kinds(Show.piles(notes)) == [["beat"], ["beat"], ["tension"], ["beat"]]
- 1 assertion.

### test "an empty section has no slots"
- assert Show.piles([]) == []   (1)

### test "past four, like notes stack together"
- input (7 notes in order): note("beat","1"), note("pays_off","2"), note("pays_off","3"), note("requires","4"), note("develops","5"), note("beat","6"), note("beat","7")
- comment: "the shape of the screenshot this came from: seven cards became four"
- assert kinds(Show.piles(notes)) == [["beat","beat","beat"], ["pays_off","pays_off"], ["requires"], ["develops"]]
- 1 assertion.

### test "the groups keep the order the notes arrived in"
- input: note("develops","1"), note("beat","2"), note("develops","3"), note("beat","4"), note("tension","5")
- comment "develops first because its first note is first, not alphabetically"
- assert Enum.map(Show.piles(notes), &hd(&1).kind) == ["develops", "beat", "tension"]
- 1 assertion.

### test "nothing is lost, whichever side of the threshold it falls on"
- `for n <- 1..12`: `notes = Enum.map(1..n, &note(Enum.at(~w(beat tension pays_off), rem(&1, 3)), "#{&1}"))` (kind by index rem(i,3): i=1 "tension", i=2 "pays_off", i=3 "beat", cycling; title "#{i}"); `flat = Show.piles(notes) |> List.flatten()`
- assert length(flat) == n, "#{n} notes must still be #{n} notes"
- assert Enum.map(flat, & &1.key) |> Enum.sort() == Enum.map(notes, & &1.key) |> Enum.sort()
- 2 assertion statements (24 executed).

### test "five notes all of different kinds stay five slots"
- comment: "grouping has nothing to group; five slots is the honest answer, and hiding four unrelated remarks behind a pager would be worse than the height it saves"
- notes = `Enum.map(~w(beat tension pays_off requires develops), &note(&1, &1))`; assert length(Show.piles(notes)) == 5   (1)

### test "the order within a stack is the order they were written"
- input: note("beat","first"), note("tension","x"), note("beat","second"), note("tension","y"), note("beat","third")
- `[beats | _] = Show.piles(notes)`; assert Enum.map(beats, & &1.title) == ["first", "second", "third"]   (1)

Behavior not obvious from the code:
- Lists of length <= 4 come back as one note per pile in original order; lists of length >= 5 are grouped by `kind` (kinds ordered by first appearance, notes within a group in original order). When a >= 5 list has all-distinct kinds the result is still five piles of one.
- Total assertions in file: 8.

======================================================================
TOTALS
======================================================================

| file | tests | assertions (statements; loop bodies counted once) |
|---|---|---|
| link_index_test.exs | 7 | 20 |
| links_index_scroll_test.exs | 6 | 15 |
| link_tag_menu_test.exs | 4 | 7 |
| linked_index_test.exs | 5 | 10 |
| public_linked_test.exs | 5 | 14 |
| public_drafts_test.exs | 7 | 11 |
| public_changes_test.exs | 6 | 12 |
| public_reading_test.exs | 13 | 27 |
| reading_owner_test.exs | 5 | 11 |
| progress_test.exs | 4 | 8 |
| live_beats_test.exs | 4 | 5 |
| read_view_test.exs | 7 | 19 |
| read_changes_test.exs | 5 | 9 |
| rewrite_apply_test.exs | 1 | 2 |
| rewrite_panel_test.exs | 8 | 17 |
| note_deck_test.exs | 5 | 16 |
| note_piles_test.exs | 7 | 8 |

TOTALS: tests=99 assertions=211 (17 files)

# PART 8. Web, stacks/tour/user settings/walkthrough/work pages

# D4: LiveView tests (test/marginalia_web/live), grouped by page/route

Conventions: all paths are under test/marginalia_web/live/. `user_fixture()` is from Marginalia.AccountsFixtures; `log_in_user(conn, user)` from ConnCase. `live(conn, path)` returns `{:ok, view, html}`. No file in this part stubs an LLM (no put_env of API keys, no FakeHub); where LLM-derived data is needed, tests write it directly to the DB (see notes per file).

Page index (route -> file):
- /links/:id?lead=SLUG -> snap_view_test
- /works/SLUG?view=... -> snap_view_test, summary_vault_test, tour_test, walkthrough_live_test, work_tabs_test, work_trace_test, work_tree_test, work_upload_fallback_test
- /stacks, /stacks/new, /stacks/:id, /stacks/:id/:ordinal -> stack_routes_test, stack_run_test, step_links_test
- /works (draft list) -> step_links_test
- /users/log-in, /users/register, /users/settings, /users/settings/confirm-email/:token -> user_live/*

---

# Route group: /links/:id (side-by-side) and /works/:slug read view

## snap_view_test.exs  (6 tests; covers pages /links/:id and /works/:slug?view=read; module MarginaliaWeb.SnapViewTest, `use MarginaliaWeb.ConnCase, async: false`)

Moduledoc: "Reading two drafts against each other, and getting back to changing one. The side-by-side view is where you see the problem; the draft's own page is where you fix it. Before this there was no way from one to the other except the back button and a search for the paragraph."

Shared setup (runs before every test, including the describe block):
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`
- `user = user_fixture()`; `pad = String.duplicate("word ", 80)`
- `make.(title, first)`: `Works.create_work(user.id, %{"title" => title, "body" => "# H\n\n#{first} #{pad}"})` then `Works.set_status(w, "read")`, returns the work.
- `long = make.("The long version", "The kettle went cold on the counter.")`
- `short = make.("The long version — in summary", "It went cold.")` (title contains an em dash)
- `node.(w, title, quote)`: `Works.insert_node(%{work_id: w.id, section_id: hd(Works.list_sections(w.id)).id, node_type: "beat", title: title, body: "b", quote: quote})` -> returns node
- `{:ok, link} = Links.get_or_create(long.id, short.id)`
- `Repo.insert!(%Marginalia.Links.LinkEdge{link_id: link.id, from_id: node.(long, "The kettle", "The kettle went cold on the counter.").id, to_id: node.(short, "It went cold", "It went cold.").id, edge_type: "echoes", rationale: "Four sentences became one."})`
- `link = Repo.update!(Ecto.Changeset.change(link, status: "linked"))`
- context: `%{conn: log_in_user(conn, user), link: link, long: long, short: short}`

### test "every paragraph offers a way back to editing it"
- Visit `/links/#{link.id}?lead=#{long.slug}` (live).
- Comment in test: "the fragment matters: it lands on the paragraph, not at the top of a document you then have to find it in"
- assert html =~ `href="/works/#{long.slug}?view=read#block-s1p1"`
- assert html =~ `href="/works/#{short.slug}?view=read#block-s1p1"`
- assert html =~ `>edit</a>`

### test "each side links to its own draft, not to the other one"
- Visit `/links/#{link.id}?lead=#{long.slug}`.
- `[lead, other] = String.split(html, ~s(id="fl-other"), parts: 2)` (the page has an element with id `fl-other` that begins the non-lead column).
- assert lead =~ long.slug
- refute lead =~ `/works/#{short.slug}?view=read#block`
- assert other =~ short.slug

### test "swapping sides swaps which draft each column edits"
- Visit `/links/#{link.id}?lead=#{short.slug}`.
- split on `id="fl-other"` as above; `[lead, _other]`.
- assert lead =~ `/works/#{short.slug}?view=read#block`

### test "the block ids it links to are the ones the draft's page renders"
- Visit `/works/#{long.slug}?view=read`.
- Comment: "the fragment is only a way back if the target exists"
- assert html =~ `id="block-s1p1"`

### describe "the draft's own page, once a comparison exists"

#### test "renders, and offers the way into it"
- Comment: "This is the case no test covered and production found in four minutes: `Side by side` only renders when a summary link exists, and it reached for `@work` inside a component that is handed `@slug`. A KeyError in a render is a dropped socket on the live page and a 500 on the first GET."
- In test: `Repo.update!(Ecto.Changeset.change(ctx.short, derived_from_id: ctx.long.id))` (short is marked derived from long).
- Visit `/works/#{long.slug}?view=read`.
- assert html =~ "Side by side"
- assert html =~ `/links/#{link.id}?lead=#{long.slug}`

#### test "and the draft with no comparison still renders without one"
- Visit `/works/#{short.slug}?view=read` (derived_from_id not set in this test).
- refute html =~ "Side by side"

Behavior not obvious from the code:
- Block ids have the form `block-s<section>p<paragraph>`; first paragraph of first section is `block-s1p1`. Body `# H\n\n<first> word word ...` yields one section and one paragraph.
- The edit link is an `<a>` whose text is exactly `edit`, href `/works/SLUG?view=read#block-s1p1`.
- `fl-other` marks the start of the second column; everything before it is the lead column. `lead` query param (a work slug) picks which draft leads.
- "Side by side" entry on the work page appears only when a summary link exists (short.derived_from_id = long.id and a Links row exists). Regression for a KeyError (`@work` vs `@slug`).
- Assertions: 3 + 3 + 1 + 1 + 2 + 1 = 11.

---

# Route group: /stacks, /stacks/new, /stacks/:id, /stacks/:id/:ordinal, and /works step links

## stack_routes_test.exs  (3 tests; covers router ordering of /stacks/new vs /stacks/:id; MarginaliaWeb.StackRoutesTest, `async: true`)

Moduledoc: "The literal routes are reachable, not shadowed by the ones with variables. `/stacks/new` sat after `/stacks/:id` and so resolved as a folder called "new", which redirected away. Nothing failed: the page rendered, it was simply the wrong page. Only clicking it found that, so this is the cheap check that clicking it again is not required."

Setup: `user = user_fixture()`; context `%{conn: log_in_user(conn, user), user: user}`.

### test "the import page is its own page"
- Visit `/stacks/new` (live).
- assert html =~ "Import a stack"
- assert html =~ `name="repo"`
- assert html =~ `name="token"`

### test "a folder id still reaches the folder"
- `assert {:error, {:live_redirect, %{to: "/stacks"}}} = live(conn, ~p"/stacks/999999")` -- a nonexistent folder id live-redirects to `/stacks`.

### test "the list is reachable"
- Visit `/stacks`; assert html =~ "Methods"

Behavior not obvious from the code:
- Literal `/stacks/new` must be matched before `/stacks/:id`.
- Unknown folder id: `live_redirect` (not plain redirect) to "/stacks"; no flash is asserted.
- Assertions: 3 + 1 + 1 = 5.

---

## stack_run_test.exs  (10 tests; covers the folder page /stacks/:id as a viewer of a background pass, `Marginalia.Runs`; MarginaliaWeb.StackRunTest, `async: false`)

Moduledoc: "The folder page as a viewer of a pass, rather than its owner. Reading a folder forwards is one model call per document, in order, because each document is told what the ones before it established. For a hundred and forty-seven pull requests that is close to two hours. It used to run in a task linked to the socket, so closing the tab killed it and the money was already gone. What is asserted here is the consequence: a page that arrives while a pass is running shows the pass, and a page that presses the button while one is running is told rather than starting a second."

Setup (every test):
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`
- `user = user_fixture()`
- `{:ok, folder} = Folders.create_folder(user.id, %{name: "Phoenix 1.8"})`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "1. A chapter", "body" => "# A chapter\n\n" <> String.duplicate("word ", 120)})`
- `{:ok, _} = Folders.move_work(user.id, work.id, folder.id)`
- Comment: "the compose control only exists once the folder has been read, so the fixture is a folder that has been"
- `Marginalia.Repo.insert!(%Marginalia.Stacks.Step{folder_id: folder.id, work_id: work.id, ordinal: 1, capability: "read a folder forwards"})`
- `key = {:stack, folder.id}`; `on_exit(fn -> Runs.forget(key) end)`
- context: `%{conn: log_in_user(conn, user), user: user, folder: folder, key: key}`

Helpers (the seam; no LLM involved, the "pass" is a function the test controls):
- `hold(key, kind)`: `me = self()`; `{:ok, _} = Runs.start(key, kind, fn -> send(me, {:running, self()}); receive do: ({:finish, v} -> v), after: (5_000 -> :timed_out) end)`; then `assert_receive {:running, pid}, 1_000`; returns pid. So `Runs.start/3` takes (key, kind atom, zero-arity fun), returns `{:ok, _}`, runs the fun in a process not linked to the caller/socket; the fun's return value is the run's result. A test finishes the pass with `send(worker, {:finish, value})`.
- `settled/0`: `_ = :sys.get_state(Runs); :ok`. Comment: "Wait for the bookkeeping, rather than for a number of milliseconds. `Runs.progress/2` is a cast and the run's completion arrives at `Runs` as a message from the task, so in both cases the call that follows raced the broadcast: `render(view)` synchronises with the *view*, which is no help if the view has not been sent anything yet. This failed about one run in nine and took a deploy with it. A call to `Runs` is queued behind whatever it has already been sent, so when this returns the broadcast has been made and the message is in the view's mailbox -- which puts it ahead of the `render` call that comes next. No sleep can promise that, and a longer one only hides it better."
- `settled/1 (worker)`: `ref = Process.monitor(worker)`; `assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000`; then `settled()`. Comment: "...and for a worker that is finishing: the task sends its result to `Runs` before it exits, so once it is gone that message is already queued there."
- `Runs` (registered name `Runs`, i.e. Marginalia.Runs) API used: `Runs.start/3`, `Runs.progress(key, opts)` (cast; keyword opts `done:`, `total:`, `stage:`), `Runs.get(key)` (map with `kind:`), `Runs.running?(key)`, `Runs.forget(key)`. It broadcasts changes to LiveViews on the folder page.

### test "a page that arrives mid-read shows the read, not the button"
- `worker = hold(key, :read)`; `Runs.progress(key, done: 4, total: 12)`; `settled()`.
- Visit `/stacks/#{folder.id}`.
- assert html =~ "4 of 12"
- assert html =~ "you can close the page"
- assert html =~ "disabled"
- Cleanup: `send(worker, {:finish, {:errors, 0}})`.

### test "a page that arrives mid-compose says which part it is on"
- `worker = hold(key, :compose)`; `Runs.progress(key, stage: "writing", done: 2, total: 5)`; `settled()`.
- Visit `/stacks/#{folder.id}`.
- assert html =~ "Composing — part 2 of 5" (em dash U+2014)
- Cleanup: `send(worker, {:finish, :ok})`.

### test "an open page follows a pass it did not start"
- Visit `/stacks/#{folder.id}` first (no run). refute html =~ "Composing".
- Comment: "something else entirely starts one -- another tab, another device"
- `worker = hold(key, :compose)`; `Runs.progress(key, stage: "outlining")`; `settled()`.
- assert render(view) =~ "Composing — outlining"
- `send(worker, {:finish, :ok})`; `settled(worker)`.
- refute render(view) =~ "Composing —"

### test "pressing the button twice does not start a second pass"
- `worker = hold(key, :read)`; visit `/stacks/#{folder.id}`.
- `html = render_click(view, "compose", %{})` (event "compose", empty params).
- assert html =~ "A read pass is already running"
- `assert %{kind: :read} = Runs.get(key), "the running pass is untouched"`
- Cleanup `send(worker, {:finish, {:errors, 0}})`.

### test "the socket going away leaves the pass alone"
- Visit `/stacks/#{folder.id}` (no run yet). `worker = hold(key, :read)`.
- assert render(view) =~ "0 of" (no progress given yet; the view already shows "0 of ...")
- Comment: "what a closed tab or a dead wifi does". `ref = Process.monitor(worker)`; `GenServer.stop(view.pid)`.
- `refute_receive {:DOWN, ^ref, :process, ^worker, _}, 200`
- `assert Process.alive?(worker), "the pass must not be linked to the socket"`
- `assert %{kind: :read} = Runs.get(key)`
- Comment: "and the next page finds it". `{:ok, _again, html} = live(conn, ~p"/stacks/#{folder.id}")`
- assert html =~ "of"
- assert Runs.running?(key)
- Cleanup `send(worker, {:finish, {:errors, 0}})`.

### test "a pass that crashes frees the folder and says so"
- Visit `/stacks/#{folder.id}` (view kept open).
- `{:ok, _} = Runs.start(key, :compose, fn -> send(me, {:running, self()}); receive do: (:crash -> raise "boom"), after: (5_000 -> :ok) end)`.
- `assert_receive {:running, worker}, 1_000`; `send(worker, :crash)`; `settled(worker)`.
- `html = render(view)`; assert html =~ "crashed"
- refute Runs.running?(key)

### test "a progress tick shows the work, not only the count"
- Visit `/stacks/#{folder.id}`; refute html =~ "the second capability".
- `worker = hold(ctx.key, :read)`.
- Comment: "what read_stack does: writes the step, then reports the tick. A second document, because a step is unique to its document in its folder."
- `Works.create_work(ctx.user.id, %{"title" => "2. Another chapter", "body" => "# Another\n\n" <> String.duplicate("word ", 120)})` -> second; `Folders.move_work(ctx.user.id, second.id, ctx.folder.id)`.
- `Repo.insert!(%Marginalia.Stacks.Step{folder_id: ctx.folder.id, work_id: second.id, ordinal: 2, capability: "the second capability"})`.
- `Runs.progress(ctx.key, done: 2, total: 12)`; `settled()`; `html = render(view)`.
- assert html =~ "2 of 12"
- assert html =~ "the second capability", message: "a forward read takes hours; showing only the counter while the steps sit unshown in the database is a page that looks like it is doing nothing"
- Cleanup finish `{:errors, 0}`.

### test "the summarise pass has its own button and its own sentence"
- Visit `/stacks/#{folder.id}`.
- assert html =~ "Summarise each document"
- assert html =~ "0 summarised"
- `worker = hold(ctx.key, :summarise)`; `Runs.progress(ctx.key, done: 1, total: 3)`; `settled()`; `html = render(view)`.
- assert html =~ "1 of 3"
- assert html =~ "one whole-document summary each", message: "the sentence has to say which pass this is: the forward read's \"waits on the one before it\" is not true of summaries"
- refute html =~ "waits on the one before it"
- Cleanup finish `{:errors, 0}`.

### test "it will not start while another pass is running"
- `worker = hold(ctx.key, :read)`; visit `/stacks/#{folder.id}`.
- `html = render_click(view, "summarise", %{})`
- assert html =~ "A read pass is already running"
- assert %{kind: :read} = Runs.get(ctx.key)
- Cleanup finish `{:errors, 0}`.

### test "relating is a pass like the others, with its own sentence"
- Visit `/stacks/#{folder.id}` (one document, one step). `refute html =~ "Relate the documents"`, message "one document is not a pair".
- Comment: "a second document, so there is something to relate it to". `Works.create_work(ctx.user.id, %{"title" => "2. Another", "body" => "# A\n\n" <> String.duplicate("word ", 120)})` -> other; move into the folder (no Step row for it).
- Comment: "relating needs each document's own map, which the forward read does not build -- a folder can be fully stepped and still have nothing to relate"
- Visit again. assert html =~ "Read each document"; refute html =~ "Relate the documents".
- `for w <- Works.list_works(ctx.user.id), do: Works.set_status(w, "read")` (both works get status "read", which is what gives a map).
- Visit again (`{:ok, view, html}`): assert html =~ "Relate the documents"; assert html =~ "0 related".
- `worker = hold(ctx.key, :relate)`; `Runs.progress(ctx.key, done: 2, total: 5, stage: "relating")`; `settled()`; `html = render(view)`.
- assert html =~ "2 of 5"
- assert html =~ "one call per pair"
- refute html =~ "waits on the one before it"
- `send(worker, {:finish, {:related, 5, 0}})`; `settled(worker)`.
- assert render(view) =~ "Related 5 pairs"

Behavior not obvious from the code:
- Run kinds: `:read`, `:compose`, `:summarise`, `:relate`. Finish values used: `{:errors, n}`, `:ok`, `{:related, pairs, errors}` (rendered "Related 5 pairs").
- Pressing "compose" or "summarise" while any pass runs returns the rendered page containing "A read pass is already running" (names the running kind) and leaves the run untouched.
- A pass is independent of the LiveView process: stopping the view must not kill the worker; a new mount finds the run via `Runs.get/running?`.
- A crashing pass (raise "boom") clears running state (`Runs.running?` false) and the open page shows text containing "crashed".
- Page text by state: running read -> "N of M", "you can close the page", a disabled button; running compose -> "Composing — part X of Y" (stage "writing" with done/total) or "Composing — <stage>" (e.g. "outlining", no counts); after finish "Composing —" disappears; idle summarise -> "Summarise each document" and "0 summarised"; running summarise -> "one whole-document summary each" and not "waits on the one before it"; "Relate the documents" button only when the folder has >= 2 documents and all are status "read", otherwise "Read each document" shows; running relate sentence "one call per pair".
- Step rows are re-read on each progress tick; a new Step's capability text appears on the page after the tick.
- Race regression: the `settled` helpers exist because of a flake (about 1 run in 9).
- Assertion count (assert/refute/assert_receive/refute_receive in test bodies, not helpers): t1 3, t2 1, t3 3, t4 2, t5 6, t6 3, t7 3, t8 5, t9 2, t10 9 = 37. (Helper assert_receive calls in hold/settled are extra.)

---

## step_links_test.exs  (5 tests; covers the /works draft list step links, `Marginalia.Stacks.steps_by_work/1`, and /stacks/:id/:ordinal; MarginaliaWeb.StepLinksTest, `async: false`)

Moduledoc: "Getting from a document to the step composed from it. A folder that has been read forwards holds two things per document -- the document, and the step the forward read made of it -- and only one of them was reachable from the list of drafts. A hundred and eleven rows, and the way to the step was to open the folder and count. The other half of this is the query: one join for the whole tree, because a list of a hundred and eleven asking per row is a hundred and eleven queries to draw a page."

Setup:
- `user = user_fixture()`; `{:ok, folder} = Folders.create_folder(user.id, %{name: "A stack"})`
- `make.(title)`: `Works.create_work(user.id, %{"title" => title, "body" => "# #{title}\n\n" <> String.duplicate("word ", 90)})` then `Folders.move_work(user.id, w.id, folder.id)`; returns w.
- `read = make.("1. The first thing")`; `unread = make.("2. The second thing")`
- `Repo.insert!(%Marginalia.Stacks.Step{folder_id: folder.id, work_id: read.id, ordinal: 1, capability: "read a folder forwards"})`
- context `%{conn: log_in_user(conn, user), user: user, folder: folder, read: read, unread: unread}`

### test "a document that became a step links to it"
- Visit `/works`.
- assert html =~ `href="/stacks/#{folder.id}/1"`
- assert html =~ "step 1"

### test "a document that has not been read has no such link"
- Visit `/works`.
- Comment: "one link, for the one document that has a step"
- assert length(Regex.scan(~r/>step \d+</, html)) == 1

### test "the lookup is one query for the whole tree"
- `by_work = Stacks.steps_by_work(ctx.user.id)` (arity 1, takes a user id; returns map work_id -> {folder_id, ordinal})
- assert by_work[read.id] == {folder.id, 1}
- assert by_work[unread.id] == nil

### test "somebody else's steps are not in this writer's map"
- `theirs = user_fixture()`; `{:ok, their_folder} = Folders.create_folder(theirs.id, %{name: "Theirs"})`; `{:ok, their_work} = Works.create_work(theirs.id, %{"title" => "Private", "body" => "# Private\n\n" <> String.duplicate("word ", 90)})` (not moved into the folder).
- `Repo.insert!(%Step{folder_id: their_folder.id, work_id: their_work.id, ordinal: 1, capability: "x"})`
- `by_work = Stacks.steps_by_work(ctx.user.id)`
- refute Map.has_key?(by_work, their_work.id)
- assert map_size(by_work) == 1

### test "the link lands on the step, not on the folder"
- Visit `/stacks/#{folder.id}/1`.
- assert html =~ "read a folder forwards"

Behavior not obvious from the code:
- /works renders a link with text `step N` (matched as `>step N<`) and href `/stacks/FOLDER_ID/ORDINAL` for every work with a Step, and nothing for works without.
- `steps_by_work/1` is scoped to the owner of the work.
- Query count is not measured; "one query" is only checked via the return shape.
- Assertions: 2 + 1 + 2 + 2 + 1 = 8.


---

# Route group: /works/:slug (reading view): summary vault and tour

## summary_vault_test.exs  (5 tests; covers /works/:slug?view=read summary vault markup; MarginaliaWeb.SummaryVaultTest, `async: false`)

Moduledoc: "What the browser needs in order to keep a summary the server will overwrite. `Summary.store/3` writes one row per section, so running it again destroys the text that was there. The vault is a per-browser safety net for exactly that, and what can be tested here is that the page hands it everything it needs: a stable key, the text, and when it was written."

Setup (all tests):
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`; `user = user_fixture()`
- `body = "# One\n\n" <> String.duplicate("word ", 300) <> "\n\n# Two\n\n" <> String.duplicate("word ", 300)` (two sections, "One" and "Two")
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `{:ok, work} = Works.set_status(work, "read")`
- context `%{conn: log_in_user(conn, user), work: work, user: user}`

Helper `summarise(work, text)` (no LLM; writes the summary straight to the DB): `section = hd(Works.list_sections(work.id))`; `section |> Ecto.Changeset.change(summary: text, summary_fingerprint: Summary.fingerprint(section), summary_body: section.body, summarised_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Marginalia.Repo.update()` -> `{:ok, s}`. Only the FIRST section (index 1) is ever summarised in these tests. Section fields used: summary, summary_fingerprint, summary_body, summarised_at.

### test "a summary carries a key, its text and its time"
- `summarise(work, "It establishes the doorway.")`; visit `/works/#{work.slug}?view=read`.
- assert html =~ `data-sum-key="#{work.slug}:1"`, message: "the key has to name the draft and the section, or two drafts share a vault"
- assert html =~ "It establishes the doorway."
- assert html =~ "data-sum-at="

### test "the container the hook writes into is left alone by LiveView"
- `summarise(work, "A summary.")`; visit `/works/#{work.slug}?view=read`.
- assert html =~ `id="sumvault-1"`
- `vault = Regex.run(~r/<div[^>]*id="sumvault-1"[^>]*>/, html) |> hd()` (the opening `<div>` tag with that id)
- assert vault =~ `phx-update="ignore"`, message: "without this a re-render wipes what the hook put there"

### test "a section with no summary offers no vault"
- No summarise call. Visit `/works/#{work.slug}?view=read`.
- refute html =~ "data-sum-key="
- refute html =~ `id="sumvault-`

### test "the hook is attached to something"
- `summarise(work, "A summary.")`; visit read view.
- assert html =~ `phx-hook="MarginaliaWeb.WorkLive.Show.SummaryVault"`, message: "a colocated hook that is never attached does nothing at all"

### test "the key survives a re-summarise, so both versions land in one vault"
- `summarise(work, "The first summary.")`; `{:ok, _view, first} = live(conn, ~p"/works/#{work.slug}?view=read")`.
- `summarise(work, "A completely different second summary.")`; `{:ok, _view, second} = live(...)` (same URL).
- `key = ~s(data-sum-key="#{work.slug}:1")`
- assert first =~ key and second =~ key
- assert second =~ "A completely different second summary."
- refute second =~ "The first summary.", message: "the server has genuinely lost it, which is why the browser keeps it"

Behavior not obvious from the code:
- Vault key format: `<slug>:<section index starting at 1>`, in attribute `data-sum-key`; the time in `data-sum-at` (present, value not asserted); container `id="sumvault-<section index>"` carrying `phx-update="ignore"`; hook name is the colocated hook module string `MarginaliaWeb.WorkLive.Show.SummaryVault` in `phx-hook`.
- Sections without a summary render no vault element and no `data-sum-key` at all (the second section "Two" never has one, and with no summary at all there is none anywhere).
- The page shows the current summary text only; the previous text is genuinely gone from the HTML (browser localStorage is the safety net, not tested here).
- Assertions: 3 + 2 + 2 + 1 + 3 = 11.

---

## tour_test.exs  (7 tests; covers the per-tab explainer on /works/:slug, `Marginalia.Tour`, `Marginalia.Accounts.mark_tour_seen/2`; MarginaliaWeb.TourTest, `async: true`)

Moduledoc: "Each tab explains itself once. The affordances it names -- a hairline in the gutter, a highlight you can hover -- are invisible until someone says they are there."

Setup (all tests):
- `user = user_fixture()`
- `body = "# A draft\n\nShe stood at the window. " <> String.duplicate("word ", 300)`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `{:ok, work} = Works.set_status(work, "read")`
- context `%{conn: log_in_user(conn, user), work: work, user: user}`

### test "the first visit to a tab explains it"
- Visit `/works/#{work.slug}?view=read`.
- assert html =~ "The page, with its notes in the margin"
- assert html =~ "hairline in the gutter" or html =~ "thin line appears"

### test "the second visit does not"
- Visit the read view twice (two separate `live/2` calls, same conn).
- refute (second) html =~ "The page, with its notes in the margin"

### test "each tab gets its own, once"
- Visit `/works/#{work.slug}?view=read` (first-visit tour is shown and marked seen).
- `html = render_click(view, "set_view", %{"view" => "graph"})`; assert html =~ "What leads to what"
- `html = render_click(view, "set_view", %{"view" => "spine"})`; assert html =~ "The whole draft at once"; refute html =~ "What leads to what"
- Comment: "going back does not explain it again"
- refute render_click(view, "set_view", %{"view" => "graph"}) =~ "What leads to what"
- `seen = Marginalia.Repo.reload!(user).seen_tours`
- assert "read" in seen and "graph" in seen and "spine" in seen (`users.seen_tours` is a list of view-name strings)

### test "help brings it back"
- Visit read view. `render_click(view, "dismiss_tour", %{})`.
- refute render(view) =~ "The page, with its notes in the margin"
- assert render_click(view, "show_help", %{}) =~ "The page, with its notes in the margin"

### test "dismissing it keeps it dismissed for that visit"
- Visit read view. refute render_click(view, "dismiss_tour", %{}) =~ "The page, with its notes"

### test "someone who has seen everything is never shown one"
- `Enum.each(Tour.views(), &Accounts.mark_tour_seen(Marginalia.Repo.reload!(user), &1))` (Tour.views/0 returns the list of view atoms; mark_tour_seen/2 takes a reloaded user and a view).
- `for v <- ~w(read graph spine threads)`: visit `/works/#{work.slug}?view=#{v}`; refute html =~ "mg-tour", message "#{v} should not explain itself again". (4 assertions.) `mg-tour` is the CSS class/id of the tour element.

### test "every tab that exists has something to say"
- No conn. `for v <- ~w(read graph spine threads trace prompts)`: `tour = Tour.for_view(String.to_existing_atom(v))` (arity 1, takes a view atom).
  - assert tour, message "#{v} has no tour"
  - assert tour.title
  - assert length(tour.points) >= 3, message "#{v} needs more than a sentence"
  (3 assertions x 6 views = 18 evaluations; 3 assert expressions in source.)
- So Tour.for_view/1 must return a struct/map with `title` (truthy) and `points` (list of >= 3) for the views read, graph, spine, threads, trace, prompts. These atoms must already exist (String.to_existing_atom).

Behavior not obvious from the code:
- Tour texts: read tour title "The page, with its notes in the margin", contains "hairline in the gutter" (or alternative "thin line appears"); graph tour contains "What leads to what"; spine tour contains "The whole draft at once".
- Visiting the read view marks "read" as seen immediately; the in-page "set_view" event with view "graph"/"spine" shows that tab's tour once and persists to the user's seen_tours.
- "dismiss_tour" hides the tour for the visit; "show_help" shows it again regardless of seen state.
- Tour for "threads", "trace", "prompts" exists though trace/prompts are owner-only tabs (see work_trace_test).
- Assertions in source: 2 + 1 + 5 + 2 + 1 + 1 + 3 = 15 (the for-loops count once each).

---

# Route group: /users/log-in, /users/register, /users/settings

## user_live/login_test.exs  (5 tests; covers /users/log-in; MarginaliaWeb.UserLive.LoginTest, `async: true`)

No moduledoc. Fixtures: `user_fixture/0` registers via `Accounts.register_user` with email `user<unique int>@example.com` and password "hello world!" (`valid_user_password()`); `set_password/1` calls `Accounts.update_user_password(user, %{password: valid_user_password()})`.

### describe "login page" -> test "renders login page"
- Visit `/users/log-in` (not logged in).
- assert html =~ "Log in"
- assert html =~ "Sign up"
- assert html =~ "Log in" (repeated in source)

### describe "user login - password" -> test "redirects if user logs in with valid credentials"
- `user = user_fixture() |> set_password()`; visit `/users/log-in`.
- `form(lv, "#login_form_password", user: %{email: user.email, password: valid_user_password(), remember_me: true})`; `conn = submit_form(form, conn)` (a real POST to the session controller).
- assert redirected_to(conn) == "/" (`~p"/"`)

### test "redirects to login page with a flash error if credentials are invalid"
- Visit `/users/log-in`. `form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})`.
- `render_submit(form, %{user: %{remember_me: true}})`; `conn = follow_trigger_action(form, conn)` (the form has phx-trigger-action after submit).
- assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
- assert redirected_to(conn) == "/users/log-in"

### describe "login navigation" -> test "redirects to registration page when the Register button is clicked"
- Visit `/users/log-in`. `lv |> element("main a", "Sign up") |> render_click() |> follow_redirect(conn, ~p"/users/register")` -> `{:ok, _login_live, login_html}`.
- assert login_html =~ "Register"

### describe "re-authentication (sudo mode)" -> test "shows login page with email filled in"
- describe setup: `user = user_fixture()`; `%{user: user, conn: log_in_user(conn, user)}` (logged-in user visiting log-in page).
- Visit `/users/log-in` (stays on the page, no redirect).
- assert html =~ "You need to reauthenticate"
- refute html =~ "Register"
- assert html =~ "Log in"
- assert html =~ `<input type="email" name="user[email]" id="login_form_password_email" value="#{user.email}"` (exact attribute order and quoting; note: no `autocomplete`/`required` between `id` and `value` can be inserted before `value`, matching is substring up to the closing quote of value)

Behavior not obvious from the code:
- Login form: `#login_form_password` with `user[email]`, `user[password]`, `user[remember_me]`; the email input id is `login_form_password_email`. Submit is a LiveView submit followed by a trigger-action POST to the session controller.
- Failure: redirect back to /users/log-in with error flash exactly "Invalid email or password". Success: redirect to "/".
- When already logged in (sudo mode), the page shows "You need to reauthenticate", has no "Register" text, and pre-fills the email with the user's email.
- "Sign up" link in `main` goes to /users/register via live navigation.
- Assertions: 3 + 1 + 2 + 1 + 4 = 11.

---

## user_live/registration_test.exs  (7 tests; covers /users/register; MarginaliaWeb.UserLive.RegistrationTest, `async: true`)

### describe "Registration page" -> test "renders registration page"
- Visit `/users/register`. assert html =~ "Register"; assert html =~ "Log in"

### test "redirects if already logged in"
- `result = conn |> log_in_user(user_fixture()) |> live(~p"/users/register") |> follow_redirect(conn, ~p"/")`
- assert {:ok, _conn} = result (logged-in visitor is redirected to "/")

### test "renders errors for invalid data"
- Visit `/users/register`. `lv |> element("#registration_form") |> render_change(user: %{"email" => "with spaces"})`.
- assert result =~ "Register"
- assert result =~ "must have the @ sign and no spaces"

### describe "register user" -> test "creates the account and sends them to log in"
- Visit `/users/register`. `email = unique_user_email()`.
- Comment: "registration navigates straight to the log-in form -- there is no confirmation email to wait for"
- `lv |> form("#registration_form", user: %{email: email, password: valid_user_password()}) |> render_submit()`
- assert_redirect(lv, ~p"/users/log-in")
- `user = Marginalia.Accounts.get_user_by_email(email)`
- assert user.confirmed_at, message "password-only registration has nothing to confirm"
- assert user.hashed_password

### test "requires a password"
- Form with `user: %{email: unique_user_email(), password: ""}` -> render_submit.
- assert html =~ "can&#39;t be blank" or html =~ "can't be blank"

### test "renders errors for duplicated email"
- Visit `/users/register`; then `user = user_fixture(%{email: "test@email.com"})` (created after mount).
- `form("#registration_form", user: %{"email" => user.email})` -> render_submit (only email given; password field left at default empty/unset).
- assert result =~ "has already been taken"

### describe "registration navigation" -> test "redirects to login page when the Log in button is clicked"
- Visit `/users/register`. `lv |> element("main a", "Log in") |> render_click() |> follow_redirect(conn, ~p"/users/log-in")` -> `{:ok, _login_live, login_html}`.
- assert login_html =~ "Log in"

Behavior not obvious from the code:
- Registration form `#registration_form` has fields `user[email]` and `user[password]`. Successful submit creates a confirmed user (confirmed_at set, hashed_password set) and live-redirects to /users/log-in; no email is sent.
- Email validation message verbatim: "must have the @ sign and no spaces" (on phx-change). Duplicate: "has already been taken" (on submit). Empty password: "can't be blank" (HTML-escaped form accepted).
- Assertions: 2 + 1 + 2 + 3 + 1 + 1 + 1 = 11.

---

## user_live/settings_test.exs  (12 tests; covers /users/settings and /users/settings/confirm-email/:token; MarginaliaWeb.UserLive.SettingsTest, `async: true`)

### describe "Settings page"

#### test "renders settings page"
- `conn |> log_in_user(user_fixture()) |> live(~p"/users/settings")`.
- assert html =~ "Change Email"
- assert html =~ "Save Password"

#### test "redirects if user is not logged in"
- `assert {:error, redirect} = live(conn, ~p"/users/settings")`
- `assert {:redirect, %{to: path, flash: flash}} = redirect` (plain redirect, not live_redirect)
- assert path == "/users/log-in"
- assert %{"error" => "You must log in to access this page."} = flash

#### test "redirects if user is not in sudo mode"
- `log_in_user(user_fixture(), token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute))` (session token authenticated 11 minutes ago) -> `live(~p"/users/settings") |> follow_redirect(conn, ~p"/users/log-in")` -> `{:ok, conn}`.
- assert conn.resp_body =~ "You must re-authenticate to access this page."

### describe "update email form" (setup: `user = user_fixture()`; `%{conn: log_in_user(conn, user), user: user}`)

#### test "updates the user email"
- `new_email = unique_user_email()`. Visit `/users/settings`. `form("#email_form", %{"user" => %{"email" => new_email}}) |> render_submit()`.
- assert result =~ "A link to confirm your email"
- assert Accounts.get_user_by_email(user.email) (old email still resolves until confirmed)

#### test "renders errors with invalid data (phx-change)"
- `element("#email_form") |> render_change(%{"action" => "update_email", "user" => %{"email" => "with spaces"}})`.
- assert result =~ "Change Email"
- assert result =~ "must have the @ sign and no spaces"

#### test "renders errors with invalid data (phx-submit)"
- `form("#email_form", %{"user" => %{"email" => user.email}}) |> render_submit()` (submitting the current email).
- assert result =~ "Change Email"
- assert result =~ "did not change"

### describe "update password form" (same setup as above)

#### test "updates the user password"
- `new_password = valid_user_password()` ("hello world!"). `form = form(lv, "#password_form", %{"user" => %{"email" => user.email, "password" => new_password, "password_confirmation" => new_password}})`.
- `render_submit(form)`; `new_password_conn = follow_trigger_action(form, conn)`.
- assert redirected_to(new_password_conn) == "/users/settings"
- assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token) (session token rotated)
- assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~ "Password updated successfully"
- assert Accounts.get_user_by_email_and_password(user.email, new_password)

#### test "renders errors with invalid data (phx-change)"
- `element("#password_form") |> render_change(%{"user" => %{"password" => "too short", "password_confirmation" => "does not match"}})`.
- assert result =~ "Save Password"
- assert result =~ "should be at least 12 character(s)"
- assert result =~ "does not match password"

#### test "renders errors with invalid data (phx-submit)"
- `form("#password_form", %{"user" => %{"password" => "too short", "password_confirmation" => "does not match"}}) |> render_submit()`.
- assert result =~ "Save Password"
- assert result =~ "should be at least 12 character(s)"
- assert result =~ "does not match password"

### describe "confirm email"
Setup: `user = user_fixture()`; `email = unique_user_email()`; `token = extract_user_token(fn url -> Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url) end)` (the url builder passed in is `&"[TOKEN]#{&1}[TOKEN]"`; the token is the part between the markers in the email's text_body); context `%{conn: log_in_user(conn, user), token: token, email: email, user: user}`.

#### test "updates the user email once"
- `{:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")`
- assert {:live_redirect, %{to: path, flash: flash}} = redirect
- assert path == "/users/settings"
- assert %{"info" => message} = flash
- assert message == "Email changed successfully."
- refute Accounts.get_user_by_email(user.email) (old email gone)
- assert Accounts.get_user_by_email(email) (new email present)
- Comment: "use confirm token again". Same visit again: `{:error, redirect}`; assert {:live_redirect, %{to: path, flash: flash}} = redirect; assert path == "/users/settings"; assert %{"error" => message} = flash; assert message == "Email change link is invalid or it has expired."

#### test "does not update email with invalid token"
- `live(conn, ~p"/users/settings/confirm-email/oops")` -> `{:error, redirect}`.
- assert {:live_redirect, %{to: path, flash: flash}} = redirect; assert path == "/users/settings"; assert %{"error" => message} = flash; assert message == "Email change link is invalid or it has expired."
- assert Accounts.get_user_by_email(user.email)

#### test "redirects if user is not logged in"
- `conn = build_conn()` (no session); visit the confirm-email URL with the valid token.
- assert {:redirect, %{to: path, flash: flash}} = redirect (plain redirect)
- assert path == "/users/log-in"
- assert %{"error" => message} = flash
- assert message == "You must log in to access this page."

Behavior not obvious from the code:
- Sudo mode: a session token authenticated more than ~10 minutes ago (test uses 11) on /users/settings redirects to /users/log-in with "You must re-authenticate to access this page." rendered on the login page (resp_body of the followed redirect).
- Unauthenticated redirect to /users/log-in is a plain `:redirect` with flash "You must log in to access this page."; confirm-email invalid/used token is a `:live_redirect` to /users/settings with error flash "Email change link is invalid or it has expired."
- Updating email does not change the email until the link is used; flash text includes "A link to confirm your email". Submitting the same email gives error containing "did not change".
- Password form is a trigger-action form (POST to a session controller), rotates the session token, redirects to /users/settings with info flash containing "Password updated successfully"; min length message "should be at least 12 character(s)", confirmation message "does not match password".
- Assertions: 2 + 4 + 1 + 2 + 2 + 2 + 4 + 3 + 3 + 10 + 5 + 4 = 42.


---

# Route group: /works/:slug read view, walkthrough overlay

## walkthrough_live_test.exs  (9 tests; covers the walkthrough (events start_walk / end_walk) on /works/:slug?view=read; MarginaliaWeb.WalkthroughLiveTest, `async: false`)

Moduledoc: "The walkthrough presses the real controls, so it goes through the real handlers. These are the guards that make that safe on somebody's actual manuscript: no row written, no model called, and the draft byte-identical at the end."

LLM mechanism: `setup` does `previous = Application.get_env(:marginalia, :deepseek_api_key)`; `Application.put_env(:marginalia, :deepseek_api_key, "test-key")`; `on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)`. This makes the LLM look "configured" (so chat / rewrite controls are enabled) but llm_endpoints still point at http://127.0.0.1:1; the tests assert the model is never called during a walkthrough (no Message rows, no Conversation rows).

Setup:
- `user = user_fixture()`
- body = `"# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\n" <> "The kettle went cold on the counter, and nobody moved to fill it again.\n\n" <> String.duplicate("word ", 260)`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `Works.set_status(work, "read")`; `section = hd(Works.list_sections(work.id))`
- context `%{conn: log_in_user(conn, user), work: work, section: section, user: user}`

Helpers:
- `threads(work)`: `Repo.aggregate(from(c in Conversation, where: c.work_id == ^work.id and not is_nil(c.block_ref)), :count)`. Comment: "`mount` creates the chat drawer's own conversation for every visit, which has nothing to do with the walkthrough -- so what is counted here is threads pinned to a paragraph, which is the only kind the tour opens." (Conversation = Marginalia.Chat.Conversation with `work_id`, `block_ref`.)
- `counts(work)`: `%{threads: threads(work), messages: Repo.aggregate(from(m in Message), :count), body: Repo.reload!(work).body}` (Message = Marginalia.Chat.Message; counted globally, all rows).
- `first_ref(view)`: `[_, ref] = Regex.run(~r/id="block-([^"]+)"/, render(view))` -> the ref of the first block element id (e.g. "s1p1"; the h1 heading "A draft" is block 1 maybe; whichever element has the first `id="block-..."`).

Events used on the view (all with a LiveView `render_click`/`render_submit` by event name): "start_walk" (%{}), "open_thread" (%{"ref" => ref, "section" => to_string(section.id)}), "thread_send" (submit, %{"message" => ...}), "suggest_rewrite" (%{"text" => ...}), "edit_block" (%{"ref" => ref}), "save_block" (submit, %{"text" => ...}), "end_walk" (%{}).

### test "the walkthrough writes nothing at all"
- Visit `/works/#{work.slug}?view=read`; `render_click(view, "start_walk", %{})`; `ref = first_ref(view)`; `before = counts(work)`.
- Comment: "every step of the read walkthrough that touches a write path"
- `render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})`
- `render_submit(view, "thread_send", %{"message" => "What is this paragraph doing?"})`
- `render_click(view, "suggest_rewrite", %{"text" => "The kettle went cold on the counter"})`
- `render_click(view, "edit_block", %{"ref" => ref})`
- `render_submit(view, "save_block", %{"text" => "A completely different paragraph."})`
- assert counts(work) == before (thread count, global message count, and work body all unchanged)

### test "the thread it opens is never inserted"
- start_walk, first_ref; `html = render_click(view, "open_thread", %{"ref" => ref, "section" => ...})`.
- Comment: "it really is on screen -- the point is that it works, not that it is skipped"
- assert html =~ "mg-thread-panel"
- assert threads(work) == 0

### test "the answer is the fixture, and it arrives"
- start_walk; open_thread; `render_submit(view, "thread_send", %{"message" => "What is this paragraph doing?"})`.
- Comment: "the delay is real, so wait for the message the same way the browser does"
- assert render(view) =~ "What is this paragraph doing?" (the user's message is shown immediately)
- `Process.sleep(1_400)`; `html = render(view)` (the canned answer arrives after a delay of < 1.4 s)
- assert html =~ "never calls the model"
- assert Repo.aggregate(from(m in Message), :count) == 0

### test "saving during the tour says so instead of doing it"
- start_walk; `render_click(view, "edit_block", %{"ref" => ref})`; `html = render_submit(view, "save_block", %{"text" => "Replaced."})`.
- assert html =~ "Nothing was saved"
- refute Repo.reload!(work).body =~ "Replaced."

### test "outside the tour the same events still write"
- NO start_walk. Comment: "no start_walk: this is the ordinary path, and it must be untouched"
- first_ref; open_thread (ref, section) ; assert threads(work) == 1.
- `render_click(view, "edit_block", %{"ref" => ref})`; `render_submit(view, "save_block", %{"text" => "Genuinely replaced."})`.
- assert Repo.reload!(work).body =~ "Genuinely replaced."

### test "ending it clears everything the tour put on the page"
- start_walk; first_ref; open_thread; `render_click(view, "edit_block", %{"ref" => ref})`.
- assert render(view) =~ "mg-thread-panel"
- `html = render_click(view, "end_walk", %{})`
- refute html =~ "mg-thread-panel"
- refute html =~ "mg-rewrite"
- refute html =~ `class="mg-edit"`
- refute html =~ `id="walk"`

### test "demo mode never grants a permission the reader does not have"
- Context uses only work, section (not the owner conn). Comment: "a guest on someone else's draft: the walkthrough stubs the model, it does not turn a reader into an editor"
- `other = log_in_user(Phoenix.ConnTest.build_conn(), user_fixture())` (a different logged-in user who does not own the work); visit `/works/#{work.slug}?view=read` as them (the page renders for non-owners: it is link-readable).
- start_walk; first_ref; open_thread; `render_click(view, "suggest_rewrite", %{"text" => "The kettle went cold on the counter"})`; `html = render(view)`.
- refute html =~ "mg-rewrite"
- assert html =~ "someone else"
- `render_click(view, "edit_block", %{"ref" => ref})`
- refute render(view) =~ `class="mg-edit"`

### test "a guest's walkthrough leaves out the steps they cannot use"
- Same non-owner conn; visit; `html = render_click(view, "start_walk", %{})`.
- assert html =~ "A thread pinned to one paragraph"
- refute html =~ "Then answer it in your own words"

### test "the overlay carries the steps, and says it is safe"
- Owner conn; visit; `html = render_click(view, "start_walk", %{})`.
- assert html =~ `id="walk"`
- assert html =~ "Nothing here is saved"
- assert html =~ "The notes sit beside the line"

Behavior not obvious from the code:
- During a walkthrough (after start_walk) the same handlers run but with demo behavior: no Conversation/Message rows inserted, no model call, no body writes; save shows "Nothing was saved"; thread panel still renders (`mg-thread-panel`); the assistant reply is a canned fixture containing "never calls the model", delivered after a real delay (test waits 1.4 s).
- After end_walk, all demo UI is removed: `mg-thread-panel`, `mg-rewrite`, `class="mg-edit"`, and the overlay `id="walk"`.
- Without start_walk, "open_thread" really inserts a pinned Conversation (threads count 1) and "save_block" really rewrites the work body.
- A non-owner in demo mode gets no rewrite UI (`mg-rewrite` absent), text containing "someone else" is shown (explaining that the draft belongs to someone else), and edit_block yields no `class="mg-edit"`. Their walkthrough omits the step text "Then answer it in your own words" and includes "A thread pinned to one paragraph".
- Assertions: 1 + 2 + 3 + 2 + 2 + 5 + 3 + 2 + 3 = 23.

---

# Route group: /works/:slug tabs (?view=read|graph|spine|threads|trace|prompts)

## work_tabs_test.exs  (7 tests; covers tab selection on /works/:slug and "set_view" event; MarginaliaWeb.WorkTabsTest, `async: true`)

Moduledoc: "Every tab must render its own pane, by click and by direct link."

Module attributes:
- `@panes` (comment: "one distinctive string per pane, taken from that pane and no other; what anyone holding the link can reach"): `[{"read", "The page"}, {"graph", "Knowledge graph"}, {"spine", "spine"}, {"threads", "thread"}]`
- `@owner_panes` (comment: "how the thing works rather than what it found: the deploy owner only"): `[{"trace", "Build trace"}, {"prompts", "How the graph was built"}]`

Setup (outer):
- `user = user_fixture()`; `body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)`
- `{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `Works.set_status(work, "read")`
- `{:ok, _} = Works.insert_node(%{work_id: work.id, node_type: "beat", title: "a beat here", narrative: "n"})` (no section_id)
- context `%{conn: log_in_user(conn, user), work: work}`

### test "an unknown view lands on the page, not on a report about it"
- Visit `/works/#{work.slug}?view=nonsense`. assert html =~ "The page"

### test "the default view is the draft itself"
- Visit `/works/#{work.slug}` (no view param).
- assert html =~ "The page"
- refute html =~ "Receipt"

### test "the tabs read in the order the work happens"
- Visit `/works/#{work.slug}`. `order = Regex.scan(~r/phx-value-view="(\w+)"/, html) |> Enum.map(&List.last/1) |> Enum.uniq()`
- assert order == ["read", "graph", "spine", "threads"] (for a non-owner user: exactly these four tab buttons, in this order, via attribute `phx-value-view`)

### describe "trace and prompts"
Setup (replaces/adds to outer context): `owner = owner_fixture()` (a user whose email is `Application.get_env(:marginalia, :owner_email)`); owner creates work `%{"title" => "Theirs", "body" => "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)}`; set_status "read"; returns `%{conn: log_in_user(build_conn(), owner), work: work}`.

#### test "the owner gets them"
- Visit `/works/#{work.slug}`. assert html =~ "Trace"; assert html =~ "Prompts"
- `for {v, marker} <- @owner_panes`: visit `/works/#{work.slug}?view=#{v}` ; assert html =~ marker, "?view=#{v} did not render #{inspect(marker)}" (trace -> "Build trace"; prompts -> "How the graph was built").

### test "nobody else gets them, by tab or by url"  (outer context: ordinary user viewing their own work)
- Visit `/works/#{work.slug}`. refute html =~ ">Trace<"; refute html =~ ">Prompts<"
- Comment: "hiding a tab is not closing a door"
- `for v <- ["trace", "prompts"]`: visit `/works/#{work.slug}?view=#{v}`; assert html =~ "The page"; refute html =~ "Build trace" (non-owner falls back to the read view).

### test "every tab switches to its own pane when clicked"
- Visit `/works/#{work.slug}`. For each of `@panes`: `html = render_click(view, "set_view", %{"view" => v})`; assert html =~ marker, "clicking #{v} did not render #{inspect(marker)}"

### test "every tab renders when reached by direct link"
- For each of `@panes`: visit `/works/#{work.slug}?view=#{v}`; assert html =~ marker, "?view=#{v} did not render #{inspect(marker)}"

Behavior not obvious from the code:
- Unknown `view` falls back to the read view ("The page"). Non-owners can never reach trace or prompts, even by URL (falls back to read view, "Build trace" absent, tab labels ">Trace<" / ">Prompts<" absent). The owner (deploy owner email) sees tabs "Trace" and "Prompts".
- Markers are loose substrings ("spine", "thread" appear in tab labels as well), so these tests prove only that the page renders and the view does not crash.
- The default (no param) view must not show text "Receipt".
- Assertions: 1 + 2 + 1 + 3 + 4 + 1 + 1 = 13 (loop bodies counted once each: owner loop 1, non-owner loop 2, set_view loop 1, direct-link loop 1; owner test also has 2 straight asserts, non-owner 2 straight refutes).

---

## work_trace_test.exs  (6 tests; covers /works/:slug?view=trace, /works/:slug/trace.json, ?view=graph direct link, retry button; MarginaliaWeb.WorkTraceTest, `async: true`)

Moduledoc: "The Trace tab. A build that cannot be inspected has to be taken on faith, which is the opposite of what this product sells."

Setup: comment "the trace is owner-only now"; `user = owner_fixture()` (email = :owner_email config); `body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)`; `Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `set_status(work, "read")`; context `%{conn: log_in_user(conn, user), work: work, user: user}`. Local helper `json_response_body(conn)` = `conn.resp_body`.

### test "shows each tool call and flags the refusals"
- `Works.record_event(%{work_id: work.id, narrative: "The Window", seq: 0, tool: "add_node", args: ~s({"type":"goal","title":"Establish the watcher"}), result: ~s({"id":1}), ok: true})`
- `Works.record_event(%{work_id: work.id, narrative: "The Window", seq: 1, tool: "link", args: ~s({"from":1,"to":2}), result: ~s({"error":"goal -> decision is the flow rule"}), ok: false})`
- `{:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=trace")`; `html = render(view)`
- assert html =~ "Establish the watcher"
- assert html =~ "The Window"
- assert html =~ "2 tool calls"
- assert html =~ "1 refused"
- Comment: "the reason is shown, not just the fact of a refusal"; assert html =~ "flow rule"

### test "says so plainly when nothing has been built yet"
- No events. Visit `?view=trace`. assert html =~ "Nothing recorded yet"

### test "the trace is the owner's alone, unlike the graph"
- Comment: "the link carries permission to read the draft, not to see how it was built"
- `other = log_in_user(build_conn(), user_fixture())`
- assert text_response(get(other, ~p"/works/#{work.slug}/trace.json"), 404) (plain HTTP GET by a non-owner returns status 404 with a text body; truthy)
- assert json_response_body(get(conn, ~p"/works/#{work.slug}/trace.json")) =~ `"events"` (owner gets a body containing the string `"events"`)
- assert text_response(get(conn, ~p"/works/#{work.id}/trace.json"), 404) (the owner using the numeric work id rather than the slug also gets 404; route is `/works/:id/trace.json` and takes the slug)

### test "the graph tab fills in when reached by a direct link"
- Comment above test: "the same bug the trace tab had: a tab reached by URL rather than by click"
- `{:ok, node} = Works.insert_node(%{work_id: work.id, node_type: "goal", title: "The watcher at the window", narrative: "n"})`
- Visit `/works/#{work.slug}?view=graph`.
- assert html =~ "data-graph"
- assert html =~ "The watcher at the window"
- assert html =~ "1 nodes" (literal "1 nodes", not pluralised)
- assert node.id

### describe "a read that produced nothing"

#### test "offers a retry, and the retry starts from clean"
- `{:ok, work} = Works.set_status(work, "read")`; visit `/works/#{work.slug}` (no view param); assert html =~ "Read again" (the work is status "read" and has no nodes).
- Comment: "leftovers from the failed run must not survive into the retry"
- `Works.insert_node(%{work_id: work.id, node_type: "beat", title: "half-written", narrative: "n"})`; `Works.record_event(%{work_id: work.id, tool: "add_node", ok: true})`.
- `render_click(view, "start_read")` (event with no params argument).
- assert Works.list_nodes(work.id) == []
- assert Works.list_events(work.id) == []
- Note: "start_read" calls `Works.reset_read(work.id)` (when status "read") and then starts `Analysis.start` asynchronously; the LLM is not configured in test (nil keys; endpoint 127.0.0.1:1 refuses), so no nodes are produced. No stubbing is done in the test.

#### test "a read with beats in it offers no retry"
- set_status "read"; insert beat node `%{work_id: work.id, node_type: "beat", title: "a real beat", narrative: "n"}`; visit `/works/#{work.slug}`.
- refute html =~ "Read again"

Behavior not obvious from the code:
- Trace tab: aggregate line "2 tool calls" and "1 refused" computed from ok flags; each event shows args (title "Establish the watcher") and narrative label ("The Window"), and for refused ones the error text from `result` ("flow rule").
- Empty state text: "Nothing recorded yet".
- /works/:slug/trace.json is owner-only; non-owners and ID-based lookups get 404 (text response); the owner's response body contains "events".
- The graph tab count text is "1 nodes".
- "Read again" button shows only when status is "read" and the work has no beat nodes; clicking "start_read" resets nodes and events first.
- Assertions: 5 + 1 + 3 + 4 + 3 + 1 = 17.


---

# Route group: /works (drafts page as a file tree)

## work_tree_test.exs  (15 tests; covers the /works LiveView (events new_folder, move, toggle, rename_start, rename, delete_folder, backfill), `Marginalia.Folders`, `Marginalia.Cases.place/3`; MarginaliaWeb.WorkTreeTest, `async: false`)

Moduledoc: "The drafts page as a file tree: making folders, and the events the drag hook pushes when something is dropped."

Setup (all tests):
- `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`; `user = user_fixture()`
- `make.(title)`: body = `"# #{title}\n\nA sentence long enough to be its own section.\n\n" <> String.duplicate("word ", 120)`; `Works.create_work(user.id, %{"title" => title, "body" => body})` -> w
- context `%{conn: log_in_user(conn, user), user: user, a: make.("Alpha draft"), b: make.("Beta draft")}` (works are not folded into any folder; status not set)
- Event semantics: `render_submit(view, "new_folder", %{"name" => ...})`, `render_hook(view, "move", %{"kind" => "work"|"folder", "id" => string id, "into" => string id | "root"})`, `render_click(view, "toggle", %{"id" => ...})`, `render_click(view, "rename_start", %{"id" => ...})`, `render_submit(view, "rename", %{"folder_id" => ..., "name" => ...})`, `render_click(view, "delete_folder", %{"id" => ...})`, `render_click(view, "backfill")`.
- Return shapes used: `Folders.create_folder(user_id, %{name: ..., parent_id: ...})` -> `{:ok, folder}`; `Folders.list_folders(user_id)` -> list of folders (structs with `name`, `parent_id`); `Folders.move_work(user_id, work_id, folder_id)` -> `{:ok, _}`; `Folders.get_folder(user_id, id)` -> folder with `parent_id`; `Works.get_work(user_id, work_id)` -> work with `folder_id`; `Folders.tree(user_id)` -> `%{folders: [node]}` where node = `%{folder: folder, works: [work], folders: [child_node]}`.

### test "with no folders it still lists the drafts"
- Visit `/works`. assert html =~ "Alpha draft"; assert html =~ "Beta draft"

### test "adding a folder puts an empty bucket on the page"
- Visit `/works`; `html = render_submit(view, "new_folder", %{"name" => "Case files"})`
- assert html =~ "Case files"
- assert html =~ "empty — drag a draft here" (em dash U+2014)
- assert [%{name: "Case files"}] = Folders.list_folders(user.id)

### test "a blank folder name is ignored rather than made"
- `render_submit(view, "new_folder", %{"name" => "   "})`
- assert Folders.list_folders(user.id) == []

### test "a duplicate folder name says so instead of appearing twice"
- Submit new_folder "Case files" twice; `html` is the second result.
- assert html =~ "already a folder with that name"
- assert length(Folders.list_folders(user.id)) == 1

### test "dropping a draft on a folder files it there"
- `{:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})`; visit.
- `render_hook(view, "move", %{"kind" => "work", "id" => to_string(a.id), "into" => to_string(f.id)})`
- assert Works.get_work(user.id, a.id).folder_id == f.id
- assert [node] = Folders.tree(user.id).folders
- assert [%{id: id}] = node.works
- assert id == a.id

### test "dropping it back on the root takes it out again"
- Folder "Case files"; `Folders.move_work(user.id, a.id, f.id)`; visit.
- `render_hook(view, "move", %{"kind" => "work", "id" => to_string(a.id), "into" => "root"})`
- assert Works.get_work(user.id, a.id).folder_id == nil

### test "dropping a folder on a folder nests it"
- Folders "Outer" and "Inner" (both top-level); visit.
- `render_hook(view, "move", %{"kind" => "folder", "id" => to_string(inner.id), "into" => to_string(outer.id)})`
- assert [node] = Folders.tree(user.id).folders
- assert node.folder.id == outer.id
- assert [child] = node.folders
- assert child.folder.id == inner.id

### test "dropping a folder into its own child is refused out loud"
- `outer = create_folder(%{name: "Outer"})`; `inner = create_folder(%{name: "Inner", parent_id: outer.id})`; visit.
- `html = render_hook(view, "move", %{"kind" => "folder", "id" => to_string(outer.id), "into" => to_string(inner.id)})`
- assert html =~ "cannot go inside itself"
- assert Folders.get_folder(user.id, outer.id).parent_id == nil

### test "collapsing a folder hides what is in it without moving anything"
- Folder "Case files" with a (Alpha draft) moved in; `{:ok, view, html} = live(...)`.
- assert html =~ "Alpha draft"
- `html = render_click(view, "toggle", %{"id" => to_string(f.id)})`; refute html =~ "Alpha draft"
- `html = render_click(view, "toggle", %{"id" => to_string(f.id)})`; assert html =~ "Alpha draft"
- assert Works.get_work(user.id, a.id).folder_id == f.id

### test "renaming a folder keeps its contents"
- Folder "Case files" with a inside; visit.
- `render_click(view, "rename_start", %{"id" => to_string(f.id)})`
- `html = render_submit(view, "rename", %{"folder_id" => to_string(f.id), "name" => "Briefs"})`
- assert html =~ "Briefs"
- refute html =~ "Case files"
- assert Works.get_work(user.id, a.id).folder_id == f.id

### test "deleting a folder from the page leaves the drafts on it"
- Folder "Case files" with a inside; visit.
- `html = render_click(view, "delete_folder", %{"id" => to_string(f.id)})`
- assert html =~ "Alpha draft"
- refute html =~ "Case files"
- assert Works.get_work(user.id, a.id) (still exists; the work moves back to the root, not deleted)

### describe "the offer to file drafts by case"
Setup (adds to outer context): `{:ok, a} = Marginalia.Cases.place(a, "Demo v. Example", "opinion")`; `{:ok, b} = Marginalia.Cases.place(b, "Demo v. Example", "dissent")`; returns `%{a: a, b: b}` (`Cases.place/3` records case name and role/kind on the work so the work "says which case"; it does not put it in a folder).

#### test "it appears only while there is something to file"
- `{:ok, view, html} = live(conn, ~p"/works")`
- assert html =~ "file them by case"
- assert html =~ "2 of these already say which case"
- `html = render_click(view, "backfill")`
- assert html =~ "Filed 2 drafts by case."
- refute html =~ "file them by case"

#### test "it builds Cases / the case name and puts both drafts in it"
- Visit; `render_click(view, "backfill")`.
- assert [cases] = Folders.tree(user.id).folders
- assert cases.folder.name == "Cases"
- assert [%{folder: %{name: "Demo v. Example"}, works: works}] = cases.folders
- assert length(works) == 2

#### test "a draft already dragged somewhere is not swept up by it"
- `pile = Folders.create_folder(user.id, %{name: "Reading pile"})`; `Folders.move_work(user.id, a.id, pile.id)`; visit.
- assert html =~ "1 of these already say which case" (only b is unfiled)
- `render_click(view, "backfill")`
- assert Works.get_work(user.id, a.id).folder_id == pile.id

### test "the count in the header is every draft, filed or not"
- Folder "Case files"; a moved into it; visit.
- Comment: "two drafts exist; one is filed, one is not"
- assert html =~ `~r/Your drafts\s*<\/h1>\s*<span class="mg-meta">2<\/span>/` (regex: the text "Your drafts", closing `</h1>`, then `<span class="mg-meta">2</span>`, whitespace allowed between)

Behavior not obvious from the code:
- Folder names: trimmed, blank ignored silently (no folder created), duplicates (same name, same parent) rejected with flash-ish text containing "already a folder with that name".
- A newly created folder renders the placeholder "empty — drag a draft here".
- Moving a folder into its own descendant is refused with the text "cannot go inside itself" and the DB is unchanged. Moving into "root" is `"into" => "root"`, giving folder_id nil.
- Collapsing ("toggle") hides folder contents purely in view state; second toggle shows them again.
- Deleting a folder via the page keeps its works (they remain listed, "Alpha draft" still on page, `Works.get_work` still returns it) and removes the folder name from the page.
- The backfill offer: text "file them by case" and "N of these already say which case" counts only works that say which case AND are not in a folder; after backfill message "Filed 2 drafts by case." and the offer disappears. Backfill creates a top-level folder "Cases" with a child folder named after the case ("Demo v. Example") containing both works. Works already in a folder are left alone.
- Header count is the total number of drafts (2), filed or not.
- Assertions: 2 + 3 + 1 + 2 + 4 + 1 + 4 + 2 + 4 + 3 + 3 + 4 + 4 + 2 + 1 = 40.

---

# Route group: POST /works/new and /works/new (upload fallback)

## work_upload_fallback_test.exs  (8 tests; covers the `/works/new` LiveView form and the plain `POST /works/new` controller path, `Works.Upload.max_words/0`, `Works.get_by_slug/1`; MarginaliaWeb.WorkUploadFallbackTest, `async: false`)

Moduledoc: "Uploading a draft when the live socket is not there. A writer had `/works/new` open in a tab. A deploy restarted the container at 19:23:18Z, their websocket died, and the longpoll fallback got `connection refused` from the proxy. Forty-five minutes later they pasted a draft and pressed Continue, and the browser did the only thing the markup told it to: a plain `POST /works/new`. Nothing answered that, so Phoenix raised NoRouteError and they got a 404 with the text gone. They tried four times. These are about that path working, and about the two things it needs to keep working: a route for the POST, and a CSRF token in the form that makes it."

Setup: `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`; returns `:ok` (no conn modification, no user; the first test visits as an anonymous visitor).

Module attribute `@draft` (heredoc, with `#{...}` interpolation; ends with a trailing newline):
```
# One

#{String.duplicate("word ", 200)}

# Two

#{String.duplicate("word ", 200)}
```
(so: "# One\n\n" + 200x"word " + "\n\n# Two\n\n" + 200x"word " + "\n")

### describe "the form the browser submits on its own"

#### test "carries an action and a CSRF token"
- Anonymous `live(conn, ~p"/works/new")`.
- `[form] = Regex.run(~r{<form[^>]*phx-submit="save".*?</form>}s, html)`
- assert form =~ `action="/works/new"`, message: "without an action the browser posts to whatever page it is on"
- assert form =~ `name="_csrf_token"`, message: "form/1 only emits the token when there is an action, and the POST is rejected without it"

### describe "POST /works/new"

#### test "saves the draft and goes to it, rather than 404ing"
- `user = user_fixture()`; `conn = log_in_user(conn, user)`.
- `conn = post(conn, ~p"/works/new", work: %{title: "Pasted", body: @draft, intent: ""})`
- assert %{slug: slug} = Works.list_works(user.id) |> List.first()
- assert redirected_to(conn) == "/works/#{slug}"
- Comment: "and the page it sends them to is really there"
- assert conn |> recycle() |> get(~p"/works/#{slug}") |> html_response(200) =~ "Pasted"

#### test "a visitor with no account at all gets one on the way in"
- Anonymous (no log_in): `conn = post(conn, ~p"/works/new", work: %{title: "Anon", body: @draft})` (no `intent` key).
- assert %{id: slug} = redirected_params(conn) (the redirect's route has path param `:id` holding the slug)
- assert Works.get_by_slug(slug).title == "Anon"

#### test "an untitled draft still saves"
- Anonymous: `post(conn, ~p"/works/new", work: %{title: "   ", body: @draft})`.
- assert Works.get_by_slug(redirected_params(conn).id).title == "Untitled draft"

### describe "when the plain POST cannot be saved"

#### test "an empty draft says so and says why a file did not arrive"
- Anonymous: `post(conn, ~p"/works/new", work: %{title: "Nothing", body: "   "})`; `html = html_response(conn, 422)`.
- assert html =~ "There&#39;s no text there yet" (HTML-escaped apostrophe)
- assert html =~ "Attaching a file needs JavaScript"
- refute html =~ "404"

#### test "the writer's text is still in the box"
- `long = String.duplicate("word ", Works.Upload.max_words() + 1)`.
- `post(conn, ~p"/works/new", work: %{title: "Too big", body: long, intent: "a test"})` (anonymous); `html = html_response(conn, 422)`.
- assert html =~ "and the limit is 120,000 for now" (so `Works.Upload.max_words()` is 120000, formatted with a thousands comma)
- Comment: "the whole reason this path exists instead of a redirect"
- assert html =~ `value="Too big"`
- assert html =~ "a test"
- assert String.contains?(html, String.duplicate("word ", 50))

#### test "nothing is written when the draft is rejected"
- `user = user_fixture()`; `conn |> log_in_user(user) |> post(~p"/works/new", work: %{title: "Nope", body: ""})`.
- assert Works.list_works(user.id) == []

### describe "the two paths agree"

#### test "the LiveView and the plain POST reject the same draft"
- `over = String.duplicate("word ", Works.Upload.max_words() + 1)`; anonymous `live(conn, ~p"/works/new")`.
- `live_error = view |> form("form[phx-submit=save]", work: %{title: "x", body: over}) |> render_submit()`
- `posted = html_response(post(conn, ~p"/works/new", work: %{title: "x", body: over}), 422)`
- assert live_error =~ "and the limit is 120,000 for now"
- assert posted =~ "and the limit is 120,000 for now"

Behavior not obvious from the code:
- The /works/new form (`<form ... phx-submit="save" ...>`) must carry `action="/works/new"` and a hidden `_csrf_token` field so that it also works as a plain browser POST when the websocket is down.
- POST /works/new accepts `work[title]`, `work[body]`, optional `work[intent]`. On success: redirect to `/works/<slug>` (route has `:id` param carrying slug). For anonymous visitors an account (guest) is created on the way in and the work is saved. Blank/whitespace title becomes "Untitled draft".
- On failure: HTTP 422 with the full /works/new page re-rendered: error text "There's no text there yet" (HTML-escaped as `There&#39;s no text there yet`) plus a note "Attaching a file needs JavaScript"; too-long text: "and the limit is 120,000 for now" (120,000 words max; `max_words()+1` words is rejected). The form retains the title (`value="Too big"`), intent ("a test") and the body text. Nothing is saved on rejection. The LiveView and the POST give the same error message.
- Assertions: 2 + 3 + 2 + 1 + 3 + 4 + 1 + 2 = 18.


---

# TOTALS

| file | tests | assertions (assert/refute/assert_receive/refute_receive/assert_redirect recorded) |
|---|---|---|
| snap_view_test | 6 | 11 |
| stack_routes_test | 3 | 5 |
| stack_run_test | 10 | 37 |
| step_links_test | 5 | 8 |
| summary_vault_test | 5 | 11 |
| tour_test | 7 | 15 |
| user_live/login_test | 5 | 11 |
| user_live/registration_test | 7 | 11 |
| user_live/settings_test | 12 | 42 |
| walkthrough_live_test | 9 | 23 |
| work_tabs_test | 7 | 13 |
| work_trace_test | 6 | 17 |
| work_tree_test | 15 | 40 |
| work_upload_fallback_test | 8 | 18 |

TOTALS: tests=115 assertions=262

# PART 9. Web, controllers/auth/guest upload/hooks/og/sitemap/applied diff

# D5: error pages, session controller, guest upload, hooks, og, sitemap, user_auth, applied diff

Conventions: all paths under test/marginalia_web/. `conn` is `Phoenix.ConnTest.build_conn()` from ConnCase (sandbox set up per test; `async: false` files here also switch the sandbox to shared mode). `log_in_user(conn, user)` = `generate_user_session_token(user)`, then `init_test_session(%{})` and `put_session(:user_token, token)`. `user_fixture(attrs)` = `Accounts.register_user(%{email: "user<unique_int>@example.com", password: "hello world!"} merged with attrs)`; the result is already confirmed. `valid_user_password()` = "hello world!". `set_password(user)` calls `Accounts.update_user_password(user, %{password: "hello world!"})` and returns the user. There are no work/folder fixtures; works are built inline with `Works.create_work(user_id, %{"title" => ..., "body" => ...})`.

LLM stubbing: none of these files stub or call an LLM. config/test.exs has API keys nil and endpoints at 127.0.0.1:1. guest_upload_test only asserts that `Marginalia.Chat.messages_sent(work.user_id) == 0` and that status stays "pending" after rejected events.

---

## controllers/error_html_test.exs  (3 tests; covers MarginaliaWeb.ErrorHTML via Phoenix.Template)
`use MarginaliaWeb.ConnCase, async: true`; `import Phoenix.Template, only: [render_to_string: 4]`.
Module doc: the generated test asserted the scaffold ("Not Found" only); that is what was replaced. These tests go through Phoenix.Template the way the endpoint reaches them, not through the module directly. "See `MarginaliaWeb.ErrorPageTest` for what the pages say."

### test "404 renders a page through the template layer"
Call: `render_to_string(MarginaliaWeb.ErrorHTML, "404", "html", [])` -> `html`.
- `html =~ "<!DOCTYPE html>"`
- `html =~ "Nothing at that address"`

### test "500 does too"
`render_to_string(MarginaliaWeb.ErrorHTML, "500", "html", [])`.
- `html =~ "<!DOCTYPE html>"`
- `html =~ "Something broke"`

### test "a status with no page of its own still renders its name"
- `render_to_string(MarginaliaWeb.ErrorHTML, "403", "html", []) == "Forbidden"` (exact equality)

Behavior not obvious from the code:
- Template-layer entry (name "404", format "html") is the contract, not `ErrorHTML.render("404.html", ...)`. Statuses without a custom template (403) fall back to the HTTP reason phrase as the entire body.
- Assertions: 5.

---

## controllers/error_json_test.exs  (2 tests; covers MarginaliaWeb.ErrorJSON)
`use MarginaliaWeb.ConnCase, async: true`.

### test "renders 404"
- `MarginaliaWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}`

### test "renders 500"
- `MarginaliaWeb.ErrorJSON.render("500.json", %{}) == %{errors: %{detail: "Internal Server Error"}}`

Behavior not obvious from the code: this is the untouched scaffold; the JSON error shape is `{"errors": {"detail": <reason phrase>}}`. Assertions: 2.

---

## controllers/user_session_controller_test.exs  (6 tests; covers POST /users/log-in, DELETE /users/log-out)
`use MarginaliaWeb.ConnCase, async: true`; `import Marginalia.AccountsFixtures`.
Top-level setup: `%{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}` (unconfirmed_user is unused by these tests; it is a user with `confirmed_at` set to nil).

### describe "POST /users/log-in - email and password"

#### test "logs the user in"
Setup: `user = set_password(user)`.
Action: `POST /users/log-in` params `%{"user" => %{"email" => user.email, "password" => "hello world!"}}`.
- `get_session(conn, :user_token)` truthy
- `redirected_to(conn) == "/"`
Then (comment: `"/" is the product landing page and deliberately carries no auth menu, so assert the logged-in menu where it actually lives`) `GET /works` on the same conn; `response = html_response(conn, 200)`:
- `response =~ user.email`
- `response =~ "/users/settings"`
- `response =~ "/users/log-out"`

#### test "logs the user in with remember me"
`user = set_password(user)`. POST /users/log-in with `"user" => %{"email" => user.email, "password" => "hello world!", "remember_me" => "true"}`.
- `conn.resp_cookies["_marginalia_web_user_remember_me"]` truthy
- `redirected_to(conn) == "/"`

#### test "logs the user in with return to"
`user = set_password(user)`. Conn is `init_test_session(user_return_to: "/foo/bar")`, then POST /users/log-in with email and password "hello world!".
- `redirected_to(conn) == "/foo/bar"`
- `Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"`

#### test "redirects to login page with invalid credentials"
User NOT given a password via set_password. POST `/users/log-in?mode=password` with `"user" => %{"email" => user.email, "password" => "invalid_password"}`.
- `Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"` (exact)
- `redirected_to(conn) == "/users/log-in"` (the `?mode=password` query is not carried)

### describe "DELETE /users/log-out"

#### test "logs the user out"
`conn |> log_in_user(user) |> delete("/users/log-out")`.
- `redirected_to(conn) == "/"`
- `refute get_session(conn, :user_token)`
- `Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"`

#### test "succeeds even if the user is not logged in"
`delete(conn, "/users/log-out")` with no session.
- `redirected_to(conn) == "/"`
- `refute get_session(conn, :user_token)`
- flash :info `=~ "Logged out successfully"`

Behavior not obvious from the code:
- Quoted comment: `"/" is the product landing page and deliberately carries no auth menu, so assert the logged-in menu where it actually lives`. The logged-in menu (email, settings link, log-out link) is on /works.
- Login failure has no per-field error; it is a generic flash plus redirect to /users/log-in.
- Remember-me cookie name `_marginalia_web_user_remember_me`.
- Assertions: 17.

---

## error_page_test.exs  (6 tests; covers MarginaliaWeb.ErrorHTML templates 404.html / 500.html)
`use MarginaliaWeb.ConnCase, async: true`; `alias MarginaliaWeb.ErrorHTML`.
Helper: `render(template)` = `ErrorHTML.render(template, []) |> Phoenix.LiveViewTest.rendered_to_string()`. Comment: `~H returns a Rendered struct rather than {:safe, iodata}; this is what Phoenix itself does with it on the way to the wire.`
Module doc: "The page nobody writes. A stranger following a stale link is fairly likely to see this one first, and the generated default is the status name as plain text on a white page with no way back to anything."

### test "404 is a page, not the words Not Found"
`html = render("404.html")`
- `html =~ "<!DOCTYPE html>"`
- `html =~ "Nothing at that address"`
- `refute html == "Not Found"`

### test "it offers somewhere to go"
`html = render("404.html")`. For each path in `/ /cases /drafts /reading`:
- `html =~ ~s(href="#{path}")` i.e. `href="/"`, `href="/cases"`, `href="/drafts"`, `href="/reading"`; failure message "a dead end with no way out of it"
(1 written, 4 evaluated.)

### test "500 does not blame the visitor"
`html = render("500.html")`
- `html =~ "Something broke"`
- `html =~ "That is this end, not yours"`

### test "neither is indexed"
For t in `404.html`, `500.html`:
- `render(t) =~ ~s(name="robots" content="noindex")` (attribute order name then content, exact)

### test "they depend on nothing that could also be broken"
`html = render("500.html")`. Comment: `its own markup and its own styles: an error page that needs the app layout, the socket or the asset pipeline is one that fails when they do. (`phx-r` is a HEEx debug annotation in dev and test builds, not something the page depends on, so it is not what is checked here.)`
- `refute html =~ "/assets/"`
- `refute html =~ "phx-hook"`
- `refute html =~ "data-phx-session"`
- `assert html =~ "<style>"`

### test "anything else keeps the plain status name"
- `ErrorHTML.render("418.html", []) == "I'm a teapot"` (exact string, not a Rendered struct; no rendered_to_string)

Behavior not obvious from the code:
- The 404/500 pages are self-contained: inline `<style>`, no app layout, no `/assets/` references, no LiveView hooks or session attrs, `noindex` robots meta, full `<!DOCTYPE html>` document, links back to `/`, `/cases`, `/drafts`, `/reading` (404).
- Other statuses are plain reason phrases returned as binaries.
- Assertions: 12 written (15 evaluated counting loop iterations).

---

## guest_upload_test.exs  (13 tests; covers guest accounts, /works, /works/new, /works/:slug, /works/:id/graph.json, /users/settings, Accounts.claim_guest_account)
`use MarginaliaWeb.ConnCase, async: true`; `import Phoenix.LiveViewTest`; `import Marginalia.AccountsFixtures`; `alias Marginalia.{Accounts, Works}`.
Module doc: "Uploading no longer needs an account. The property that must survive that: a guest can reach their own drafts and nobody else's."

### describe "arriving with no account"

#### test "is let in, and given a guest of their own"
Anonymous `GET /works/new`.
- `html_response(conn, 200) =~ "Upload a draft"`
- pattern `%{user: user} = conn.assigns.current_scope`
- `user.is_guest` truthy
- `get_session(conn, :user_token)` truthy (a session token is created for the guest)

#### test "the same session keeps the same guest"
`conn = get(conn, "/works/new")`; `first = conn.assigns.current_scope.user.id`. Then same conn `get("/works")`.
- `conn.assigns.current_scope.user.id == first`

#### test "two different visitors get two different guests"
`a = get(conn, "/works/new").assigns.current_scope.user`; `b = get(build_conn(), "/works/new").assigns.current_scope.user`.
- `a.id != b.id`
- `a.email != b.email`

### describe "a draft is unlisted, and the link is the permission"
Setup: `{:ok, guest} = Accounts.create_guest_user()` (arity 0); `{:ok, work} = Works.create_work(guest.id, %{"title" => "Mine", "body" => String.duplicate("w ", 300)})`; returns `%{guest: guest, work: work}`.

#### test "the url carries an unguessable slug, not the row id"
- `byte_size(work.slug) >= 20`
- `refute work.slug == to_string(work.id)`
- `Works.get_by_slug(work.slug).id == work.id`

#### test "a guessed slug gets nothing"
`conn = get(conn, "/works")` (becomes a guest session, not the owner).
- `{:error, {:live_redirect, %{to: "/works"}}} = live(conn, "/works/1")` (pattern match; a numeric id live-redirects to /works)
- `text_response(get(conn, "/works/1/graph.json"), 404)` (a 404 with text body)

#### test "the owner sees it as theirs, with a link to hand out"
`conn = log_in_user(conn, guest)`; `{:ok, _view, html} = live(conn, "/works/#{work.slug}")`.
- `html =~ "Mine"`
- `html =~ "Copy link"`
- `refute html =~ "reading someone&#39;s draft"` (HTML-escaped apostrophe)

#### test "someone with the link can read it"
`conn = get(conn, "/works")` (a different guest), `live(conn, "/works/#{work.slug}")`.
- `html =~ "Mine"`
- `html =~ "reading someone&#39;s draft"`
- `refute html =~ "Copy link"`

#### test "but cannot spend the owner's model credit or change the draft"
Different guest: `conn = get(conn, "/works")`, `{:ok, view, _html} = live(conn, "/works/#{work.slug}")`. For event in `send`, `build_graph`, `start_read`: params = `%{"message" => "hello"}` for "send", `%{}` otherwise;
- `render_click(view, event, params) =~ "You can read it, not change it"` (for each of the 3)
Then (comment: `nothing was asked, nothing was started`):
- `Marginalia.Chat.messages_sent(work.user_id) == 0`
- `Works.get_by_slug(work.slug).status == "pending"`

#### test "it does not show up in anyone else's list"
`conn = get(conn, "/works")`.
- `refute html_response(conn, 200) =~ "Mine"`

### describe "settings still need a real account"

#### test "a guest is sent to sign up, not to log in — they have nothing to log in with"
`{:ok, guest} = Accounts.create_guest_user()`; `conn |> log_in_user(guest) |> get("/users/settings")`.
- `redirected_to(conn) == "/users/register"`

#### test "a real account gets in"
`conn |> log_in_user(user_fixture()) |> get("/users/settings")`.
- `html_response(conn, 200)` (truthy)

### describe "claiming the account keeps the work"

#### test "a guest becomes a real user and keeps everything they uploaded"
Setup inline: guest via `Accounts.create_guest_user()`; work `Works.create_work(guest.id, %{"title" => "Kept", "body" => String.duplicate("w ", 300)})`.
Call: `Accounts.claim_guest_account(guest, %{email: "real@example.com", password: "a-long-enough-password"})` (atom keys) -> `{:ok, claimed}`.
- `refute claimed.is_guest`
- `claimed.email == "real@example.com"`
- `claimed.id == guest.id`
- comment `same row, so the work never moved`: `[%{id: id}] = Works.list_works(claimed.id)` (pattern, exactly one work); `id == work.id`
- `Accounts.get_user_by_email_and_password("real@example.com", "a-long-enough-password")` truthy

#### test "claiming a real account is refused"
`user = user_fixture()`; `Accounts.claim_guest_account(user, %{email: "x@y.com", password: "whatever-long"})`.
- `{:error, _} = ...` (any error value)

Behavior not obvious from the code:
- Anonymous visitors get a persisted guest user (`is_guest` true, unique email) and a session token on first hit of a guest-enabled route; the same session keeps the same guest.
- Work slug is the public identifier (>= 20 bytes, not the numeric id). A numeric id in the URL is a miss for LiveView (live_redirect to /works) and a 404 text response on the graph.json controller route.
- Non-owner viewers can read, but `send`, `build_graph`, `start_read` events return the message "You can read it, not change it" and have no side effects (no chat message counted against the owner, status stays "pending").
- The owner view shows "Copy link"; the non-owner view shows a "reading someone's draft" banner (HTML-escaped `&#39;`).
- /users/settings sends a guest to /users/register (not /users/log-in); real users get 200.
- Claiming reuses the same row/id, so works remain attached.
- Assertions: 31 written (the for-loop in the credit test evaluates 3 times).

---

## hooks_test.exs  (5 tests; covers static structure of lib/marginalia_web/**/*.ex colocated JS hooks)
`use ExUnit.Case, async: true` (not ConnCase; no DB). Reads files relative to cwd: `@dir "lib/marginalia_web"`, `files()` = `Path.wildcard("lib/marginalia_web/**/*.ex")`.
Module doc: "Every colocated hook a template asks for exists. `phx-hook=".Composer"` was on the chat's form and no `.Composer` hook was ever written. LiveView throws `unknown hook` on the client, the binding for that element never attaches, and the chat opened, accepted typing and sent nothing. Nothing server-side could catch it: `Phoenix.LiveViewTest` renders the markup and never runs a hook, so the whole suite was green while the feature was dead. This is the cheap structural check that would have — the names have to match, and a typo or a deletion fails here."

For a Blimp port: this test inspects Elixir/HEEx source text. The equivalent contract: every client-side hook the templates reference has a definition; every definition is referenced; methods called on `this` exist; selectors a hook uses match markup.

### test "every colocated hook referenced by a template is defined in the same module"
For each .ex file, each match of regex `phx-hook="\.([A-Za-z0-9_]+)"`; missing if the file's source does not contain the literal `ColocatedHook} name=".<name>"`.
- `missing == []` (message lists `path: phx-hook=".name"`)

### test "every colocated hook that is defined is actually used"
For each regex match `ColocatedHook\} name="\.([A-Za-z0-9_]+)"`; unused if the source does not contain `phx-hook=".<name>"`.
- `unused == []`

### test "every this.method() a hook calls is defined in that hook"
`@builtin` = `mounted beforeUpdate updated destroyed disconnected reconnected pushEvent pushEventTo handleEvent upload uploadTo js` (allowed without definition).
Hook body extraction: `~r/ColocatedHook\} name="\.([A-Za-z0-9_]+)">(.*?)<\/script>/s` -> (name, body).
Calls: `~r/this\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/`, uniq. Defined if body matches `~r/(^|[\s,{])NAME\s*\([^)]*\)\s*\{/` (method shorthand) or `~r/this\.NAME\s*=/` (assigned onto this).
- `missing == []` (message "called but never defined")
Comment: `Second time in two days that a JavaScript feature died in silence: first a hook that was never written, then a method deleted while its caller stayed. Both looked like "the button does nothing", both passed every test, because LiveViewTest renders markup and never runs a hook.`

### test "every element a hook reaches for exists in the markup"
Preceded by comment: `A hook reaching for an element that is not there fails the same silent way: `querySelector` returns null, the next line throws or quietly does nothing, and the markup and the tests both look fine. `.fl-mid` went missing from my own reading of the page for an hour on exactly this.`
Haystack = for every file: source with `ColocatedHook}.*?</script>` (dotall) removed, plus `written(source)`, plus `applied(source)`, joined with newlines. Comment: "The templates, with hook bodies stripped — or a selector would satisfy itself. Plus the class names a hook *writes*: the graph hook builds its own `<g class="gnode">` and then selects it, which is legitimate and invisible to a template-only search."
- `written/1`: all matches of `~r/(?:class|id)=\\?["'][^"'<>]{0,120}\\?["']/` (class/id attribute text in markup a hook builds as a string).
- `applied/1`: class names from `classList.(add|toggle)("x")` (regex `~r/classList\.(?:add|toggle)\(\s*["']([A-Za-z0-9_-]+)["']/`) plus the static prefix of `className = "..."` (regex `~r/className\s*=\s*[`"']([^`"'$]*)/`). Comments: "`add` and `toggle` put a class on something; `remove` and `contains` only ask about one, and counting those let a selector satisfy itself — `classList.contains("fl-mid")` kept this test green while the element it names had been renamed away." And: "`el.className = "fl-card k-" + kind` is the other way a hook names something it builds. The static part is the name; whatever gets interpolated after it is not this test's business." Also: the graph hook marks its selected node with `classList.add("sel")` and then selects `.gnode.sel`; "Nothing in any template says "sel", and that is correct."
- `tokens/1` of each hook body: selector string literals in `querySelector|querySelectorAll|closest|matches(` with quote delimiters; selectors containing `${` are skipped; tokens are `[.#][A-Za-z0-9_-]+` or `\[data-[a-z-]+\]`, uniq. Comment: "An interpolated id — `#blk-other-${ref}` — is only half a name, and the halves either side of the `${}` are not selectors at all: without stripping them this flags `.dataset` and `.peerRef` as missing elements. Anything built at runtime is out of scope here; what this checks is the static names."
- `present?/2`: whole-name match `(?<![A-Za-z0-9_-])NAME(?![A-Za-z0-9_-])`. Comment: "A whole name, not a substring: renaming `fl-mid` to `fl-middle` left the old token still "found" inside the new one, so the first version of this test passed against exactly the bug it was written for." `bare/1` strips leading `.` or `#`, or the `[`..`]` of a data attr.
- `missing == []` (message "selectors that match nothing in any template")

### test "the chat's composer is among them"
`source = File.read!("lib/marginalia_web/components/link_chat.ex")`
- `source =~ ~s(phx-hook=".Composer")`
- `source =~ ~s(ColocatedHook} name=".Composer")`

Behavior not obvious from the code:
- Four structural invariants over hook JS embedded in server templates (above). Each is a regression test for a hook that silently did nothing.
- Requires lib/marginalia_web/components/link_chat.ex to exist with a hook named `.Composer` (phx-hook=".Composer").
- Assertions: 6.

---

## og_test.exs  (6 tests; covers Open Graph / Twitter meta and canonical on /, /cases, /cases/:slug, /cases/:slug/read; plus the og-cases.png asset)
`use MarginaliaWeb.ConnCase, async: false`; `import Phoenix.LiveViewTest`; `import Marginalia.AccountsFixtures`; `alias Marginalia.{Cases, Works}`.
Module doc: "What a link to this looks like pasted somewhere else. Every page used to declare `og:url` as the site root, so a link to a particular case unfurled as a link to the front door — and told the scrapers the two were the same page."

Setup (every test): `Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})`; `previous_owner = Application.get_env(:marginalia, :owner_email)`; `Application.put_env(:marginalia, :owner_email, "owner@example.com")`; `on_exit` restores (if previous was nil, `delete_env`; else `put_env` previous). Comment: "Restored, not deleted. `delete_env` drops the configured value instead of putting it back, so anything reading `:owner_email` afterwards sees nil rather than what config set — invisible in one run, because ExUnit runs the async readers before these sync modules, and immediately fatal under --repeat-until-failure, which is the tool for finding flakes."
Data: `owner = user_fixture(%{email: "owner@example.com"})`; `body = "# x\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 200)`; `{:ok, w} = Works.create_work(owner.id, %{"title" => "Some v. Case — Opinion", "body" => body})`; `{:ok, w} = Works.set_status(w, "read")`; `{:ok, _} = Cases.place(w, "Some v. Case", "opinion")` (case name "Some v. Case", kind "opinion"; yields case slug `some-v-case`). Conn is NOT logged in (anonymous). Returns `%{conn: conn}`.

Helper `meta(html, property)`: first match of `~r/<meta[^>]*(?:property|name)="PROP"[^>]*content="([^"]*)"/`, returns captured content or nil (property/name attr must precede content attr).

### test "the front page keeps the product's own card"
`live(conn, "/")`.
- `meta(html, "og:image") =~ "/images/og.png"`
- `meta(html, "og:url") =~ ~r{/$}` (ends with a slash)

### describe "the cases micro-site"

#### test "has its own title, description and card"
`live(conn, "/cases")`.
- `meta(html, "og:title") == "The term, read closely"`
- `meta(html, "og:image") =~ "/images/og-cases.png"`
- `meta(html, "twitter:image") =~ "/images/og-cases.png"`
- `meta(html, "og:image:alt") =~ "dissent arguing with that exact sentence"`

#### test "the description counts the corpus rather than describing it"
`live(conn, "/cases")`.
- `meta(html, "og:description") =~ "1 Supreme Court cases, 1 documents"` (literal; no singularization)
- `meta(html, "og:description") =~ "anchored to a sentence in both"`

#### test "each page declares itself, not the site root"
Three sequential lives:
- `/cases`: `meta(html, "og:url") =~ "/cases"`
- `/cases/some-v-case`: `meta(html, "og:url") =~ "/cases/some-v-case"`; `meta(html, "og:title") == "Some v. Case"`
- `/cases/some-v-case/read`: `meta(html, "og:url") =~ "/cases/some-v-case/read"`

#### test "the canonical link agrees with og:url"
`live(conn, "/cases/some-v-case")`.
- `[_, href] = Regex.run(~r/<link[^>]*rel="canonical"[^>]*href="([^"]*)"/, html)` matches (rel before href in the tag)
- `href == meta(html, "og:url")`

### test "the card image is actually there"
No conn. `path = Path.join(:code.priv_dir(:marginalia), "static/images/og-cases.png")`.
- `File.exists?(path)`
- `<<_::binary-16, 2400::32, 1260::32, _::binary>> = File.read!(path)` (PNG IHDR: width 2400, height 1260 as big-endian 32-bit ints at byte offsets 16 and 20). Comment: `1.91:1 at 2x, which is what every card wants`.

Behavior not obvious from the code:
- og:url per page is that page's own path (an absolute URL containing the path); canonical equals og:url exactly.
- The home page keeps /images/og.png; cases pages use /images/og-cases.png for og:image and twitter:image.
- Case page og:title is the case name alone.
- Description is computed from data: "<N> Supreme Court cases, <M> documents" with the seeded counts (1 and 1) and a fixed phrase "anchored to a sentence in both".
- Depends on priv/static/images/og-cases.png existing at 2400x1260.
- Assertions: 16.

---

## sitemap_test.exs  (6 tests; covers GET /sitemap.xml and priv/static/robots.txt)
`use MarginaliaWeb.ConnCase, async: false`; `import Marginalia.AccountsFixtures`; `alias Marginalia.Works`.
Module doc: "What a crawler is told exists. Several hundred public pages and almost none reachable by following links: a crawler that lands on one linked pair cannot discover the other three hundred and ninety-one. robots.txt says what not to visit; this says what is there."

Setup: `Sandbox.mode(Marginalia.Repo, {:shared, self()})`; `Marginalia.Cache.invalidate_all()`; `on_exit(&Marginalia.Cache.invalidate_all/0)`; `owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})` (config/runtime.exs default "bobbbygrayson@gmail.com" unless OWNER_EMAIL set); `stranger = user_fixture()`; `body = "# H\n\nALPHA. " <> String.duplicate("word ", 300)`; `mine` = `Works.create_work(owner.id, %{"title" => "Mine", "body" => body})`; `theirs` = `Works.create_work(stranger.id, %{"title" => "Theirs", "body" => body})`. Returns `%{conn, mine, theirs}`. Works are left in default status (not set to "read").
Helper `fetch(conn)` = `conn |> get("/sitemap.xml") |> response(200)`.

### test "it is xml and lists the public entry points"
- `xml =~ "<?xml"`
- `xml =~ "<urlset"`
- for path in `/ /cases /drafts /linked /reading`: `xml =~ "<loc>http://localhost:4000#{path}</loc>"` (message "#{path} is missing"). E.g. `<loc>http://localhost:4000/</loc>`, `<loc>http://localhost:4000/cases</loc>`. (5 evaluated.)

### test "the owner's drafts are in it"
- `fetch(conn) =~ "/drafts/#{mine.slug}</loc>"`

### test "nobody else's draft is"
- `refute fetch(conn) =~ theirs.slug`

### test "a draft with no changes has no changes page listed"
- `refute fetch(conn) =~ "/drafts/#{mine.slug}/changes"`, message: "listing hundreds of empty diffs asks a crawler to fetch hundreds of empty tables"

### test "a draft with changes does"
`section = hd(Works.list_sections(mine.id))`; `block = section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))`; `{:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))`; `Marginalia.Cache.invalidate_all()` (the sitemap is cached).
- `fetch(conn) =~ "/drafts/#{mine.slug}/changes</loc>"`

### test "robots.txt points at it"
`robots = File.read!("priv/static/robots.txt")` (cwd-relative file read, no HTTP).
- `robots =~ "Sitemap:"`
- `robots =~ "/sitemap.xml"`
- `robots =~ "Disallow: /works/"`, message "the private pages stay disallowed"

Behavior not obvious from the code:
- Only the owner's (config `:owner_email`) works are public drafts at `/drafts/<slug>`; others' are excluded entirely (checked by slug).
- `/drafts/<slug>/changes` is listed only if the draft has at least one applied change (replace_block); otherwise omitted.
- Base URL in the test environment is `http://localhost:4000`.
- The sitemap is cached (`Marginalia.Cache`); tests invalidate it before and after.
- Assertions: 10 written (13 evaluated).

---

## user_auth_test.exs  (28 tests; covers MarginaliaWeb.UserAuth plugs and on_mount hooks)
`use MarginaliaWeb.ConnCase, async: true`; aliases `Phoenix.LiveView`, `Marginalia.Accounts`, `Marginalia.Accounts.Scope`, `MarginaliaWeb.UserAuth`; `import Marginalia.AccountsFixtures`.
Constants: `@remember_me_cookie "_marginalia_web_user_remember_me"`; `@remember_me_cookie_max_age 60 * 60 * 24 * 14` (1209600 s, 14 days).
Top-level setup: conn gets `Map.replace!(:secret_key_base, MarginaliaWeb.Endpoint.config(:secret_key_base))` and `init_test_session(%{})`; returns `%{user: %{user_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}`. These tests call plug functions directly (not through the router), so a port needs the equivalents of log_in_user/3, log_out_user/1, fetch_current_scope_for_user/2, on_mount/4, require_authenticated_user/2, disconnect_sessions/1.

### describe "log_in_user/3"

#### test "stores the user token in the session"
`conn = UserAuth.log_in_user(conn, user)`.
- `token = get_session(conn, :user_token)` truthy
- `get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"`
- `redirected_to(conn) == "/"`
- `Accounts.get_user_by_session_token(token)` truthy

#### test "clears everything previously stored in the session"
`conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)`.
- `refute get_session(conn, :to_be_removed)`

#### test "keeps session when re-authenticating"
conn has `assign(:current_scope, Scope.for_user(user))`, session `:to_be_removed => "value"`, then `log_in_user(user)` (same user).
- `get_session(conn, :to_be_removed)` truthy (kept)

#### test "clears session when user does not match when re-authenticating"
`other_user = user_fixture()`; conn assign `current_scope: Scope.for_user(other_user)`, session `:to_be_removed`, `log_in_user(user)`.
- `refute get_session(conn, :to_be_removed)`

#### test "redirects to the configured path"
`put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)`.
- `redirected_to(conn) == "/hello"`

#### test "clears the return-to path from the session after logging in"
Assign current_scope for same user, put_session :user_return_to "/hello", `log_in_user(user)`.
- `redirected_to(conn) == "/hello"`
- `refute get_session(conn, :user_return_to)`

#### test "writes a cookie if remember_me is configured"
`conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})`.
- `get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]`
- `get_session(conn, :user_remember_me) == true`
- pattern `%{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]`
- `signed_token != get_session(conn, :user_token)` (cookie is signed)
- `max_age == 1209600`

#### test "redirects to settings when user is already logged in"
conn has `assign(:current_scope, Scope.for_user(user))`, then `log_in_user(user)` (no return_to).
- `redirected_to(conn) == "/users/settings"`

#### test "writes a cookie if remember_me was set in previous session"
First: `conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})`.
- `get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]`
- `get_session(conn, :user_remember_me) == true`
Then `conn |> recycle() |> Map.replace!(:secret_key_base, endpoint secret) |> fetch_cookies() |> init_test_session(%{user_remember_me: true})`. Comment: "the conn is already logged in and has the remember_me cookie set, now we log in again and even without explicitly setting remember_me, the cookie should be set again". `conn |> UserAuth.log_in_user(user, %{})`:
- pattern `%{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]`
- `signed_token != get_session(conn, :user_token)`
- `max_age == 1209600`
- `get_session(conn, :user_remember_me) == true`

### describe "logout_user/1" (describe string is "logout_user/1"; function under test is `UserAuth.log_out_user/1`)

#### test "erases session and cookies"
`user_token = Accounts.generate_user_session_token(user)`; conn puts session :user_token, `put_req_cookie(@remember_me_cookie, user_token)`, `fetch_cookies()`, `UserAuth.log_out_user()`.
- `refute get_session(conn, :user_token)`
- `refute conn.cookies[@remember_me_cookie]`
- pattern `%{max_age: 0} = conn.resp_cookies[@remember_me_cookie]`
- `redirected_to(conn) == "/"`
- `refute Accounts.get_user_by_session_token(user_token)` (token deleted in DB)

#### test "broadcasts to the given live_socket_id"
`live_socket_id = "users_sessions:abcdef-token"`; `MarginaliaWeb.Endpoint.subscribe(live_socket_id)`; `conn |> put_session(:live_socket_id, live_socket_id) |> UserAuth.log_out_user()`.
- `assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}`

#### test "works even if user is already logged out"
`conn |> fetch_cookies() |> UserAuth.log_out_user()`.
- `refute get_session(conn, :user_token)`
- pattern `%{max_age: 0} = conn.resp_cookies[@remember_me_cookie]`
- `redirected_to(conn) == "/"`

### describe "fetch_current_scope_for_user/2"

#### test "authenticates user from session"
`user_token = Accounts.generate_user_session_token(user)`; `conn |> put_session(:user_token, user_token) |> UserAuth.fetch_current_scope_for_user([])`.
- `conn.assigns.current_scope.user.id == user.id`
- `conn.assigns.current_scope.user.authenticated_at == user.authenticated_at`
- `get_session(conn, :user_token) == user_token`

#### test "authenticates user from cookies"
`logged_in_conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})`; `user_token = logged_in_conn.cookies[@remember_me_cookie]`; `%{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]`. Then the setup conn (no session token) with `put_req_cookie(@remember_me_cookie, signed_token)` and `fetch_current_scope_for_user([])`.
- `conn.assigns.current_scope.user.id == user.id`
- `conn.assigns.current_scope.user.authenticated_at == user.authenticated_at`
- `get_session(conn, :user_token) == user_token`
- `get_session(conn, :user_remember_me)` truthy
- `get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(user_token)}"`

#### test "does not authenticate if data is missing"
`_ = Accounts.generate_user_session_token(user)`; `conn = UserAuth.fetch_current_scope_for_user(conn, [])` (nothing in session/cookie).
- `refute get_session(conn, :user_token)`
- `refute conn.assigns.current_scope` (nil assigned)
This plug does not create a guest; guest creation is elsewhere (see guest_upload_test).

#### test "reissues a new token after a few days and refreshes cookie"
`logged_in_conn` as above with remember_me; `token = logged_in_conn.cookies[@remember_me_cookie]`; `%{value: signed_token} = logged_in_conn.resp_cookies[...]`. `offset_user_token(token, -10, :day)` (sets inserted_at and authenticated_at to 10 days ago in the DB). `{user, _} = Accounts.get_user_by_session_token(token)` (user re-read, authenticated_at 10 days ago). conn: `put_session(:user_token, token)`, `put_session(:user_remember_me, true)`, `put_req_cookie(@remember_me_cookie, signed_token)`, `fetch_current_scope_for_user([])`.
- `conn.assigns.current_scope.user.id == user.id`
- `conn.assigns.current_scope.user.authenticated_at == user.authenticated_at` (carried over from the old token)
- `new_token = get_session(conn, :user_token)` truthy
- `new_token != token`
- pattern `%{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]`
- `new_signed_token != signed_token`
- `max_age == 1209600`

### describe "on_mount :mount_current_scope"
describe-level setup: `%{conn: UserAuth.fetch_current_scope_for_user(conn, [])}`. Calls `UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})` where `session = conn |> put_session(...) |> get_session()` (the full session map).

#### test "assigns current_scope based on a valid user_token"
session `:user_token` = `Accounts.generate_user_session_token(user)`.
- pattern `{:cont, updated_socket} = ...`
- `updated_socket.assigns.current_scope.user.id == user.id`

#### test "assigns nil to current_scope assign if there isn't a valid user_token"
session :user_token "invalid_token".
- `{:cont, updated_socket}`
- `updated_socket.assigns.current_scope == nil`

#### test "assigns nil to current_scope assign if there isn't a user_token"
session `get_session(conn)` with no token.
- `{:cont, updated_socket}`
- `updated_socket.assigns.current_scope == nil`

### describe "on_mount :require_authenticated"
Socket for the failing cases: `%LiveView.Socket{endpoint: MarginaliaWeb.Endpoint, assigns: %{__changed__: %{}, flash: %{}}}`.

#### test "authenticates current_scope based on a valid user_token"
valid token in session, bare `%LiveView.Socket{}`.
- `{:cont, updated_socket} = UserAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})`
- `updated_socket.assigns.current_scope.user.id == user.id`

#### test "redirects to login page if there isn't a valid user_token"
session token "invalid_token".
- `{:halt, updated_socket} = ...`
- `updated_socket.assigns.current_scope == nil`

#### test "redirects to login page if there isn't a user_token"
no token in session.
- `{:halt, updated_socket} = ...`
- `updated_socket.assigns.current_scope == nil`
(Test names say "redirects", but assertions only check the :halt tuple and a nil scope; the redirect target is not checked.)

### describe "on_mount :require_sudo_mode"

#### test "allows users that have authenticated in the last 10 minutes"
Valid token in session; socket with endpoint and `__changed__`/`flash`.
- `assert {:cont, _updated_socket} = UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)`

#### test "redirects when authentication is too old"
`eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)`; `user = %{user | authenticated_at: eleven_minutes_ago}`; `user_token = Accounts.generate_user_session_token(user)`; `{user, token_inserted_at} = Accounts.get_user_by_session_token(user_token)`.
- `DateTime.compare(token_inserted_at, user.authenticated_at) == :gt`
- `assert {:halt, _updated_socket} = UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)`
The token's inserted_at is later than authenticated_at; the sudo check uses authenticated_at.

### describe "require_authenticated_user/2"
describe-level setup: `%{conn: UserAuth.fetch_current_scope_for_user(conn, [])}`.

#### test "redirects if user is not authenticated"
`conn |> fetch_flash() |> UserAuth.require_authenticated_user([])`.
- `conn.halted`
- `redirected_to(conn) == "/users/log-in"`
- `Phoenix.Flash.get(conn.assigns.flash, :error) == "You must log in to access this page."`

#### test "stores the path to redirect to on GET"
Three variants, each `%{conn | ...} |> fetch_flash() |> UserAuth.require_authenticated_user([])`:
1. `path_info: ["foo"], query_string: ""`: `halted_conn.halted`; `get_session(halted_conn, :user_return_to) == "/foo"`
2. `path_info: ["foo"], query_string: "bar=baz"`: `halted`; `get_session(...) == "/foo?bar=baz"`
3. `path_info: ["foo"], query_string: "bar", method: "POST"`: `halted`; `refute get_session(halted_conn, :user_return_to)` (not stored for non-GET)

#### test "does not redirect if user is authenticated"
conn `assign(:current_scope, Scope.for_user(user))` then `require_authenticated_user([])`.
- `refute conn.halted`
- `refute conn.status`

### describe "disconnect_sessions/1"

#### test "broadcasts disconnect messages for each token"
`tokens = [%{token: "token1"}, %{token: "token2"}]`; subscribes to `"users_sessions:#{Base.url_encode64(token)}"` for each; `UserAuth.disconnect_sessions(tokens)`.
- `assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: "users_sessions:dG9rZW4x"}` (base64url of "token1")
- `assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: "users_sessions:dG9rZW4y"}` (base64url of "token2")

Behavior not obvious from the code:
- This is the phx.gen.auth UserAuth suite. Default post-login redirect is "/"; logging in while already logged in as the same user redirects to "/users/settings".
- The session token is the raw binary; the cookie value is the same token signed (so it differs from the raw value). Live socket id is `"users_sessions:" <> Base.url_encode64(token)`.
- Re-login keeps session contents only if the current scope's user matches the user logging in; otherwise the session is cleared. Login with return_to clears the return_to key after redirecting.
- Token reissue: sessions older than a few days (test uses 10 days) get a fresh token and a refreshed remember-me cookie, while `authenticated_at` is carried over from the old token.
- Sudo mode: authenticated within 10 minutes passes, 11 minutes fails.
- Assertions: 70 written (some evaluate more than once).

---

## live/applied_diff_test.exs  (4 tests; covers LiveView /works/:slug?view=read, events edit_block, save_block, dismiss_applied)
`use MarginaliaWeb.ConnCase, async: false`; `import Phoenix.LiveViewTest`; `import Marginalia.AccountsFixtures`; `alias Marginalia.Works`.
Module doc: "What a change looks like the moment it lands. Accepting a rewrite used to drop you back into plain prose: the dimming cleared, the panel closed, and nothing on the page said what had just happened to the paragraph you were looking at."

Setup: `Sandbox.mode(Marginalia.Repo, {:shared, self()})`; `user = user_fixture()`;
```
body =
  "# One\n\nALPHA the first paragraph. " <>
    String.duplicate("word ", 150) <>
    "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 150)
```
`{:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})`; `{:ok, work} = Works.set_status(work, "read")`; returns `%{conn: log_in_user(conn, user), work: work}` (owner logged in).
Helper `first_ref(view)`: `[_, ref] = Regex.run(~r/id="block-([^"]+)"/, render(view))`, the first `id="block-<ref>"` in the rendered page (the first paragraph block).

All tests visit `live(conn, "/works/#{work.slug}?view=read")`.

### test "an edit shows the before against the after, in place"
`ref = first_ref(view)`; `render_click(view, "edit_block", %{"ref" => ref})`; `html = render_submit(view, "save_block", %{"text" => "REPLACED ENTIRELY."})`.
- `html =~ "REPLACED ENTIRELY."`
- `html =~ "mg-applied"`, message "the paragraph shows what it replaced"
- `html =~ "Before"`
- `html =~ "ALPHA"`, message "the text that went has to still be visible"

### test "it is dismissable, and then the paragraph is just a paragraph"
Same edit and save, then `html = render_click(view, "dismiss_applied", %{})`.
- `refute html =~ "mg-applied"`
- `html =~ "REPLACED ENTIRELY."`, message "the new text stays; only the comparison goes"

### test "an untouched draft shows no comparison anywhere"
`{:ok, _view, html} = live(...)`.
- `refute html =~ "mg-applied"`

### test "only the paragraph that changed shows one"
Same edit and save.
- `length(Regex.scan(~r/class="mg-applied"/, html)) == 1` (exactly one element whose class attribute is exactly `mg-applied`)
- `html =~ "BRAVO the second paragraph."`, message "the other paragraph is untouched prose"

Behavior not obvious from the code:
- After `save_block`, the replaced block renders inline with class `mg-applied` containing a "Before" label and the old text (ALPHA...), alongside the new text; `dismiss_applied` removes only the comparison.
- Events: `edit_block` (params `%{"ref" => ref}`) via render_click, `save_block` via `render_submit` (params `%{"text" => ...}`), `dismiss_applied` (empty params) via render_click, all on the work page in `?view=read`.
- Work status is "read" so blocks render.
- Assertions: 9.

---

TOTALS: tests=79 assertions=178 (as written; loop bodies counted once)

| file | tests | assertions (as written) |
|---|---|---|
| controllers/error_html_test.exs | 3 | 5 |
| controllers/error_json_test.exs | 2 | 2 |
| controllers/user_session_controller_test.exs | 6 | 17 |
| error_page_test.exs | 6 | 12 |
| guest_upload_test.exs | 13 | 31 |
| hooks_test.exs | 5 | 6 |
| og_test.exs | 6 | 16 |
| sitemap_test.exs | 6 | 10 |
| user_auth_test.exs | 28 | 70 |
| live/applied_diff_test.exs | 4 | 9 |
