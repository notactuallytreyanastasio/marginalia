# The schema

Marginalia's 34 Postgres migrations, collapsed into one SQLite schema,
version 1. No data migrates, so the history is not kept; the column order is
the final Postgres order (columns added by later migrations come last). The
migrations in `priv/repo/migrations` are the truth this was written from.

Type mapping: `citext` is `TEXT COLLATE NOCASE`; `utc_datetime` is `TEXT`
("YYYY-MM-DD HH:MM:SS", UTC); `boolean` is `INTEGER NOT NULL DEFAULT 0/1`;
arrays and maps are `TEXT` holding JSON; `binary` is `TEXT` holding hex;
`references(..., on_delete: :delete_all)` is `ON DELETE CASCADE`, `:nilify_all`
is `ON DELETE SET NULL`. The one `CHECK` constraint that survived
(`links_are_between_two_works`) is kept; the conversation one was dropped by a
later migration.

Tables the rewrite adds because Phoenix kept their contents in memory:
`sessions`, `runs` and `versions`. `schema_migrations` records what ran.

Every table that had `timestamps()` has both columns defaulting to the
current UTC second, the same expression Alloy's `timestamps()` uses.
`users_tokens` and `messages` had `updated_at: false` and keep only
`inserted_at`.

    let stamp = "TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now'))";

## Accounts

    let accountsSql(): List<String> {
      [
        "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT COLLATE NOCASE NOT NULL, hashed_password TEXT, confirmed_at TEXT, inserted_at ${stamp}, updated_at ${stamp}, is_admin INTEGER NOT NULL DEFAULT 0, llm_provider TEXT, is_guest INTEGER NOT NULL DEFAULT 0, seen_tours TEXT NOT NULL DEFAULT '[]')",
        "CREATE UNIQUE INDEX users_email_index ON users (email)",
        "CREATE INDEX users_is_guest_index ON users (is_guest)",
        "CREATE TABLE users_tokens (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, token TEXT NOT NULL, context TEXT NOT NULL, sent_to TEXT, authenticated_at TEXT, inserted_at ${stamp})",
        "CREATE INDEX users_tokens_user_id_index ON users_tokens (user_id)",
        "CREATE UNIQUE INDEX users_tokens_context_token_index ON users_tokens (context, token)",
        "CREATE TABLE sessions (id TEXT PRIMARY KEY, user_token_id INTEGER REFERENCES users_tokens(id) ON DELETE SET NULL, data TEXT NOT NULL DEFAULT '{}', inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE INDEX sessions_user_token_id_index ON sessions (user_token_id)",
      ]
    }

## Folders

`works.folder_id` points here, so folders come before works. A folder's
sibling names are unique per user, separately for roots and for children.

    let foldersSql(): List<String> {
      [
        "CREATE TABLE folders (id INTEGER PRIMARY KEY, name TEXT NOT NULL, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL, inserted_at ${stamp}, updated_at ${stamp}, published_at TEXT, slug TEXT)",
        "CREATE INDEX folders_user_id_index ON folders (user_id)",
        "CREATE INDEX folders_parent_id_index ON folders (parent_id)",
        "CREATE UNIQUE INDEX folders_sibling_name_index ON folders (user_id, parent_id, name) WHERE parent_id IS NOT NULL",
        "CREATE UNIQUE INDEX folders_root_name_index ON folders (user_id, name) WHERE parent_id IS NULL",
        "CREATE UNIQUE INDEX folders_slug_index ON folders (slug)",
        "CREATE INDEX folders_published_at_index ON folders (published_at)",
      ]
    }

## Works and what hangs off them

    let worksSql(): List<String> {
      [
        "CREATE TABLE works (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, title TEXT NOT NULL, intent TEXT, body TEXT NOT NULL, word_count INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending', status_detail TEXT, first_impression TEXT, inserted_at ${stamp}, updated_at ${stamp}, slug TEXT NOT NULL, source_url TEXT, collection TEXT, collection_role TEXT, folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL, baseline_body TEXT, derived_from_id INTEGER REFERENCES works(id) ON DELETE SET NULL)",
        "CREATE INDEX works_user_id_id_index ON works (user_id, id)",
        "CREATE UNIQUE INDEX works_slug_index ON works (slug)",
        "CREATE INDEX works_collection_index ON works (collection)",
        "CREATE INDEX works_folder_id_index ON works (folder_id)",
        "CREATE INDEX works_derived_from_id_index ON works (derived_from_id)",
        "CREATE TABLE sections (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, word_count INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending', inserted_at ${stamp}, updated_at ${stamp}, summary TEXT, summary_fingerprint TEXT, summarised_at TEXT, summary_covers TEXT DEFAULT '[]', summary_follows TEXT DEFAULT '[]', summary_sets_up TEXT, summary_dropped TEXT DEFAULT '[]', summary_body TEXT)",
        "CREATE UNIQUE INDEX sections_work_id_ordinal_index ON sections (work_id, ordinal)",
        "CREATE TABLE nodes (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, section_id INTEGER REFERENCES sections(id) ON DELETE CASCADE, node_type TEXT NOT NULL, title TEXT NOT NULL, body TEXT, quote TEXT, ordinal INTEGER NOT NULL DEFAULT 0, inserted_at ${stamp}, updated_at ${stamp}, status TEXT NOT NULL DEFAULT 'pending', narrative TEXT)",
        "CREATE INDEX nodes_work_id_node_type_ordinal_index ON nodes (work_id, node_type, ordinal)",
        "CREATE INDEX nodes_section_id_index ON nodes (section_id)",
        "CREATE INDEX nodes_work_id_narrative_index ON nodes (work_id, narrative)",
        "CREATE TABLE edges (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, from_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, to_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, edge_type TEXT NOT NULL DEFAULT 'leads_to', ordinal INTEGER NOT NULL DEFAULT 0, inserted_at ${stamp}, updated_at ${stamp}, rationale TEXT)",
        "CREATE INDEX edges_work_id_ordinal_index ON edges (work_id, ordinal)",
        "CREATE UNIQUE INDEX edges_from_id_to_id_edge_type_index ON edges (from_id, to_id, edge_type)",
        "CREATE TABLE conversations (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, title TEXT, inserted_at ${stamp}, updated_at ${stamp}, mode TEXT NOT NULL DEFAULT 'read', anchor_kind TEXT NOT NULL DEFAULT 'work', section_id INTEGER REFERENCES sections(id) ON DELETE CASCADE, block_ref TEXT, quote TEXT, resolved_at TEXT)",
        "CREATE INDEX conversations_work_id_id_index ON conversations (work_id, id)",
        "CREATE INDEX conversations_work_id_anchor_kind_index ON conversations (work_id, anchor_kind)",
        "CREATE INDEX conversations_section_id_index ON conversations (section_id)",
        "CREATE UNIQUE INDEX conversations_work_block_index ON conversations (work_id, block_ref) WHERE block_ref IS NOT NULL",
        "CREATE TABLE messages (id INTEGER PRIMARY KEY, conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, inserted_at ${stamp})",
        "CREATE INDEX messages_conversation_id_id_index ON messages (conversation_id, id)",
        "CREATE TABLE graph_events (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, narrative TEXT, seq INTEGER NOT NULL DEFAULT 0, tool TEXT NOT NULL, args TEXT, result TEXT, ok INTEGER NOT NULL DEFAULT 1, node_id INTEGER, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE INDEX graph_events_work_id_seq_index ON graph_events (work_id, seq)",
        "CREATE TABLE corrections (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, kind TEXT NOT NULL, about TEXT NOT NULL, ruling TEXT, section_ordinal INTEGER, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE INDEX corrections_work_id_index ON corrections (work_id)",
        "CREATE TABLE revisions (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, section_id INTEGER REFERENCES sections(id) ON DELETE SET NULL, section_ordinal INTEGER, seq INTEGER NOT NULL, before TEXT NOT NULL, after TEXT NOT NULL, origin TEXT NOT NULL DEFAULT 'edit', note TEXT, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE INDEX revisions_work_id_index ON revisions (work_id)",
        "CREATE UNIQUE INDEX revisions_work_id_seq_index ON revisions (work_id, seq)",
        "CREATE TABLE work_attachments (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'text', content TEXT NOT NULL, byte_size INTEGER NOT NULL DEFAULT 0, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE UNIQUE INDEX work_attachments_work_id_name_index ON work_attachments (work_id, name)",
        "CREATE TABLE document_summaries (id INTEGER PRIMARY KEY, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, summary TEXT, throughline TEXT, movements TEXT DEFAULT '[]', guidelines TEXT DEFAULT '[]', tensions TEXT DEFAULT '[]', fingerprint TEXT, dropped TEXT DEFAULT '[]', inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE UNIQUE INDEX document_summaries_work_id_index ON document_summaries (work_id)",
      ]
    }

## Links, cuts, stacks, mutterings

`cut_picks` was created and then dropped; it is not here.

    let linksSql(): List<String> {
      [
        "CREATE TABLE links (id INTEGER PRIMARY KEY, a_work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, b_work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, status TEXT NOT NULL DEFAULT 'pending', summary TEXT, error TEXT, inserted_at ${stamp}, updated_at ${stamp}, CONSTRAINT links_are_between_two_works CHECK (a_work_id <> b_work_id))",
        "CREATE UNIQUE INDEX links_a_work_id_b_work_id_index ON links (a_work_id, b_work_id)",
        "CREATE INDEX links_b_work_id_index ON links (b_work_id)",
        "CREATE TABLE link_edges (id INTEGER PRIMARY KEY, link_id INTEGER NOT NULL REFERENCES links(id) ON DELETE CASCADE, from_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, to_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, edge_type TEXT NOT NULL, rationale TEXT, ordinal INTEGER NOT NULL DEFAULT 0, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE UNIQUE INDEX link_edges_link_id_from_id_to_id_edge_type_index ON link_edges (link_id, from_id, to_id, edge_type)",
        "CREATE INDEX link_edges_link_id_ordinal_index ON link_edges (link_id, ordinal)",
        "CREATE INDEX link_edges_from_id_index ON link_edges (from_id)",
        "CREATE INDEX link_edges_to_id_index ON link_edges (to_id)",
        "CREATE TABLE cuts (id INTEGER PRIMARY KEY, title TEXT NOT NULL, question TEXT, status TEXT NOT NULL DEFAULT 'draft', status_detail TEXT, thesis TEXT, threads TEXT, tensions TEXT, not_supported TEXT, dropped TEXT, content_sha TEXT, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL, inserted_at ${stamp}, updated_at ${stamp}, scope TEXT NOT NULL DEFAULT 'folder', members TEXT)",
        "CREATE INDEX cuts_user_id_index ON cuts (user_id)",
        "CREATE INDEX cuts_folder_id_index ON cuts (folder_id)",
        "CREATE UNIQUE INDEX cuts_one_per_folder_index ON cuts (user_id, folder_id) WHERE folder_id IS NOT NULL",
        "CREATE TABLE stack_steps (id INTEGER PRIMARY KEY, folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE, work_id INTEGER NOT NULL REFERENCES works(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, capability TEXT, requires TEXT DEFAULT '[]', lesson TEXT, pitfall TEXT, pitfall_quote TEXT, excerpts TEXT, fingerprint TEXT, dropped TEXT DEFAULT '[]', inserted_at ${stamp}, updated_at ${stamp}, mechanism TEXT, watch_for TEXT, revised_by INTEGER, revision TEXT, revision_quote TEXT, deep_dropped TEXT DEFAULT '[]', deepened_at TEXT)",
        "CREATE UNIQUE INDEX stack_steps_folder_id_work_id_index ON stack_steps (folder_id, work_id)",
        "CREATE INDEX stack_steps_folder_id_index ON stack_steps (folder_id)",
        "CREATE TABLE stack_stories (id INTEGER PRIMARY KEY, folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE, title TEXT, opening TEXT, movements TEXT, closing TEXT, uncovered TEXT DEFAULT '[]', dropped TEXT DEFAULT '[]', fingerprint TEXT, inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE UNIQUE INDEX stack_stories_folder_id_index ON stack_stories (folder_id)",
        "CREATE TABLE mutterings (id INTEGER PRIMARY KEY, text TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'cron', inserted_at ${stamp}, updated_at ${stamp})",
        "CREATE UNIQUE INDEX mutterings_text_index ON mutterings (text)",
      ]
    }

## Run state

What Phoenix kept in ETS and process memory: background runs, and a counter
per topic that writers bump so a page can tell something changed.

    let runtimeSql(): List<String> {
      [
        "CREATE TABLE runs (key TEXT PRIMARY KEY, status TEXT NOT NULL, progress TEXT, detail TEXT, pid INTEGER, started_at TEXT, finished_at TEXT)",
        "CREATE TABLE versions (topic TEXT PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0)",
      ]
    }

## Version 2: the import listing

The import wizard lists up to five hundred pull requests per session and the
page keeps two flags on each (`shown`: it passes the pattern, `chosen`: it is
ticked). The rows are keyed by a hash of the session id and swept a day after
they were made. The table came to the schema in version 2; before that
`pages_import` created it on first use with `CREATE TABLE IF NOT EXISTS`, which
was a second place a table was defined.

    let importSql(): List<String> {
      [
        "CREATE TABLE import_pulls (sid TEXT NOT NULL, pos INTEGER NOT NULL, repo TEXT NOT NULL, number INTEGER NOT NULL, title TEXT NOT NULL, url TEXT, state TEXT, draft INTEGER NOT NULL DEFAULT 0, base TEXT, head TEXT, updated_at TEXT, created_at TEXT, merged_at TEXT, shown INTEGER NOT NULL DEFAULT 0, chosen INTEGER NOT NULL DEFAULT 0, made TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')), PRIMARY KEY (sid, pos))",
      ]
    }

## Version 3: rendered blocks

A paragraph of a draft renders to the same HTML every time its text and its
highlight are the same, and a 12,000-word draft of emphasis-heavy prose took
1.4 s to render on every view. `render_cache` keeps that HTML by the SHA-256
of the block's Markdown source; the `reading` library loads a page's keys in
one query and inserts the misses. Rows are swept when thirty days old.

    let renderCacheSql(): List<String> {
      [
        "CREATE TABLE render_cache (key TEXT PRIMARY KEY, html TEXT NOT NULL, made TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')))",
      ]
    }

## The list

`dbMigrate` runs each script whose version is not in `schema_migrations`,
in order. Later changes are new versions appended here; a version is never
edited once a database has it.

    export let dbSchemaVersions(): List<Pair<Int, String>> {
      let groups = [accountsSql(), foldersSql(), worksSql(), linksSql(), runtimeSql()];
      let stmts = new ListBuilder<String>();
      var g = 0;
      while (g < groups.length) {
        stmts.addAll(groups[g]);
        g += 1;
      }
      let script = stmts.toList().join(";\n") { (p: String): String => p };
      let v2 = importSql().join(";\n") { (p: String): String => p };
      let v3 = renderCacheSql().join(";\n") { (p: String): String => p };
      [new Pair<Int, String>(1, script), new Pair<Int, String>(2, v2), new Pair<Int, String>(3, v3)]
    }
