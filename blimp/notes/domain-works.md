# Marginalia domain layer: specification for the Temper rewrite

Scope: `lib/marginalia/` (works, analysis, chat, document, summary, rewrite, reading, selection, diff, markdown, runs, cache, recovery, tour, walkthrough, graph) and the migrations for the tables they touch. Everything below was read from the Elixir source and its tests in `test/marginalia/`; where a behaviour was uncertain it was run (Elixir 1.19 on this machine) and the observed output is quoted.

Toolchain note from the coordinator: the shell has no JAVA_HOME and `/usr/bin/java` is a stub. `export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; export PATH="$JAVA_HOME/bin:$PATH"` WORKED (`java -version` prints OpenJDK 21.0.12.1). openjdk@27 and plain openjdk were not needed. The `temper` binary itself is not on PATH in this shell; only the JDK was verified.

Conventions used in this document:

- "Elixir `\s`" means PCRE `\s` WITHOUT the `u` flag: ASCII whitespace only (space, `\t`, `\n`, `\v`, `\f`, `\r`). NBSP (U+00A0) and U+200B are NOT matched (verified: `String.split("a b c", ~r/\s+/, trim: true)` gives `["a b","c"]`). With the `u` flag (`~r/\s/u`) Unicode whitespace including NBSP matches. Each regex below says which it is.
- "word count" = number of maximal runs of non-ASCII-whitespace characters: `length(String.split(text, ~r/\s+/, trim: true))`. Used everywhere (`Work.word_count`, `Section.word_count`, `Upload.word_count`, `Rewrite.word_count`, `Segmenter`).
- Positions: `String.slice`, `String.length`, `String.graphemes` are GRAPHEME based; `:binary.match` / `binary_part` are BYTE based (UTF-8). Where the code mixes them it is called out; a port working in one consistent unit (code points) is acceptable only where this document says the quirk is harmless.
- Timestamps: all tables use `timestamps(type: :utc_datetime)`: `inserted_at`, `updated_at`, second precision, NOT NULL, set by Ecto on insert/update. `messages` has `inserted_at` only.
- Every id is a Postgres `bigserial` primary key (Ecto default `id`, `:id`/bigint), foreign keys are bigint.
- Database is PostgreSQL (partial indexes, citext on users, `ALTER COLUMN ... DROP NOT NULL`).
- Ecto 3.14.2, ecto_sql 3.14.0, MDEx 0.13.5, Req 0.7.4, Jason 1.4.5, Phoenix PubSub 2.3.0, Floki 0.38.4 (Floki is NOT used anywhere in this scope).
- Ecto default validation messages used below: required -> `can't be blank`; inclusion -> `is invalid`; length max -> `should be at most %{count} character(s)`; number greater_than -> overridden to `looks empty`; unique constraint -> `has already been taken`.

---

## 1. Data model

Only tables in scope plus the foreign keys they depend on. `users` (id, email citext, ...) is outside scope; `works.user_id` references it.

### 1.1 `works`

Created by `20260915000422_create_works`, extended by later migrations.

| column | type | null | default | origin |
|---|---|---|---|---|
| id | bigserial PK | no | | |
| user_id | bigint FK users(id) ON DELETE CASCADE | no | | create_works |
| title | varchar(255) | no | | create_works |
| intent | text | yes | | create_works |
| body | text | no | | create_works |
| word_count | integer | no | 0 | create_works |
| status | varchar(255) | no | `'pending'` | create_works (pending / reading / read / failed) |
| status_detail | varchar(255) | yes | | create_works. NOTE varchar(255): `Analysis.run` writes `"spine unavailable: #{inspect(reason)}"` here; a long reason (an `{:http, status, 300-char body}` tuple) exceeds 255 and Postgres rejects it (see hazards). |
| first_impression | text | yes | | create_works |
| slug | varchar(255) | no | | add_slug_to_works (added nullable, backfilled with random slugs, then SET NOT NULL) |
| source_url | varchar(255) | yes | | add_source_url_to_works |
| collection | varchar(255) | yes | | add_collection_to_works |
| collection_role | varchar(255) | yes | | add_collection_to_works |
| folder_id | bigint FK folders(id) ON DELETE SET NULL | yes | | create_folders |
| baseline_body | text | yes | | create_revisions |
| derived_from_id | bigint FK works(id) ON DELETE SET NULL | yes | | a_draft_knows_what_it_condenses |
| inserted_at, updated_at | timestamp(0) | no | | |

Indexes: `works(user_id, id)`; unique `works(slug)`; `works(collection)`; `works(folder_id)`; `works(derived_from_id)`. (Folder-related columns published_at/slug live on `folders`, out of scope.)

Ecto schema `Marginalia.Works.Work` fields: slug, title, intent, source_url, collection, collection_role, body, baseline_body, word_count (default 0), status (default "pending"), status_detail, first_impression; belongs_to user, folder, derived_from (Work); has_many sections (preload_order asc ordinal), nodes.

`Work.changeset(work, attrs)`:
1. cast: title, intent, body, status, status_detail, first_impression, source_url, collection, collection_role, baseline_body, derived_from_id. (user_id, folder_id, slug and word_count are NOT castable; user_id is set on the struct by `create_work`.)
2. `put_slug`: if the current slug (struct or change) is nil, set slug = 16 cryptographically random bytes, URL-safe base64 without padding (22 chars). Never regenerated.
3. validate_required [:title, :body] (whitespace-only strings count as blank; Ecto 3.14 trims for emptiness).
4. validate_length title max 200 (`should be at most 200 character(s)`).
5. validate_inclusion status in `pending reading read failed`.
6. put_word_count: if body (change or field) is a binary, set word_count = word count of body. (`put_change` of a value equal to the struct's existing value records no change.)
7. validate_number word_count greater_than 0, message `looks empty`. In practice this never fires for new works: an empty body yields word_count 0 equal to the default 0, so no change is registered and only `body can't be blank` appears.

`Works.change_work(work \\ %Work{}, attrs \\ %{})` = `Work.changeset`.

### 1.2 `sections`

| column | type | null | default |
|---|---|---|---|
| id | bigserial | no | |
| work_id | bigint FK works ON DELETE CASCADE | no | |
| ordinal | integer | no | |
| title | varchar(255) | no | |
| body | text | no | |
| word_count | integer | no | 0 |
| status | varchar(255) | no | `'pending'` (pending/reading/read/failed; not validated by the changeset) |
| summary | text | yes | |
| summary_fingerprint | varchar(255) | yes | |
| summarised_at | timestamp(0) | yes | |
| summary_covers | text[] | yes | `{}` |
| summary_follows | integer[] | yes | `{}` |
| summary_sets_up | text | yes | |
| summary_dropped | text[] | yes | `{}` |
| summary_body | text | yes | |
| inserted_at, updated_at | | no | |

Unique index `sections(work_id, ordinal)`. Ordinals are 1-based and contiguous at creation. Ecto schema adds `has_many nodes`, `belongs_to work`. `Section.changeset`: cast [ordinal, title, body, status, word_count]; validate_required [ordinal, title, body]. (Sections are inserted by `insert_all` and updated by `Ecto.Changeset.change`, so this changeset is barely used.)

### 1.3 `nodes`

| column | type | null | default |
|---|---|---|---|
| id | bigserial | no | |
| work_id | FK works CASCADE | no | |
| section_id | FK sections CASCADE | yes | |
| node_type | varchar(255) | no | |
| title | text | no | |
| body | text | yes | |
| quote | text | yes | |
| ordinal | integer | no | 0 |
| status | varchar(255) | no | `'pending'` |
| narrative | varchar(255) | yes | |
| inserted_at, updated_at | | no | |

Indexes: `nodes(work_id, node_type, ordinal)`, `nodes(section_id)`, `nodes(work_id, narrative)`. Note `narrative` is varchar(255); narrative names come from the model and are not truncated by the code.

`Node.changeset`: cast [work_id, section_id, node_type, title, body, quote, ordinal, status, narrative]; validate_required [work_id, node_type, title]; validate_inclusion node_type in `goal decision option observation action outcome revisit beat spine thread note question` (`Node.types/0`); validate_inclusion status in `pending chosen rejected superseded completed`. Messages `can't be blank`, `is invalid`.

Meaning of node types: `beat` (a move in one section, always has section_id and a verified quote), `spine`, `thread`, `question` (work-level, section_id nil, no quote), `note` (unused by the code in scope), and the seven decision-graph types written by `DecisionGraph`.

### 1.4 `edges`

| column | type | null | default |
|---|---|---|---|
| id | bigserial | no | |
| work_id | FK works CASCADE | no | |
| from_id | FK nodes CASCADE | no | |
| to_id | FK nodes CASCADE | no | |
| edge_type | varchar(255) | no | `'leads_to'` |
| ordinal | integer | no | 0 |
| rationale | text | yes | |
| inserted_at, updated_at | | no | |

Indexes: `edges(work_id, ordinal)`; UNIQUE `edges(from_id, to_id, edge_type)`. `Works.link/6` inserts with `on_conflict: :nothing`, so a duplicate silently returns `{:ok, struct_with_nil_id}`. Edge types in use: `follows` (beat chain), `leads_to` (spine chain, decision graph), and the Weave set `develops pays_off requires tension realises asks_about`. `Edge.changeset`: cast [work_id, from_id, to_id, edge_type, ordinal, rationale]; validate_required [work_id, from_id, to_id, edge_type]. The edge_type is not validated against a list.

### 1.5 `conversations`, `messages`

`conversations`: id; work_id FK works CASCADE NOT NULL (it was made nullable and then NOT NULL again; the `link_id` column and its check constraint were added and fully removed in 20260916010000); title varchar(255) null; mode varchar(255) NOT NULL default `'read'`; anchor_kind varchar(255) NOT NULL default `'work'`; section_id FK sections CASCADE null; block_ref varchar(255) null; quote text null; resolved_at timestamp(0) null; timestamps. Indexes: `conversations(work_id, id)`, `conversations(work_id, anchor_kind)`, `conversations(section_id)`, UNIQUE partial `conversations_work_block_index` on `(work_id, block_ref) WHERE block_ref IS NOT NULL`.

`Conversation.changeset`: cast [work_id, title, mode, anchor_kind, section_id, block_ref, quote, resolved_at]; validate_inclusion anchor_kind in `work block span`; validate_required [work_id]; validate_inclusion mode in `Chat.Editor.mode_names()` = `["read","provoke","bounce"]` (message `is invalid`).

`messages`: id; conversation_id FK conversations CASCADE NOT NULL; role varchar(255) NOT NULL; content text NOT NULL; `inserted_at` only. Index `messages(conversation_id, id)`. `Message.changeset`: cast [conversation_id, role, content]; required all three; role in `["user","assistant"]`.

### 1.6 `graph_events`

id; work_id FK CASCADE NOT NULL; narrative varchar(255) null; seq integer NOT NULL default 0; tool varchar(255) NOT NULL; args text; result text; ok boolean NOT NULL default true; node_id integer (plain integer, not a FK); timestamps. Index `graph_events(work_id, seq)`. Changeset: cast [work_id, narrative, seq, tool, args, result, ok, node_id]; required [work_id, tool].

### 1.7 `corrections`

id; work_id FK CASCADE NOT NULL; kind varchar(255) NOT NULL; about text NOT NULL; ruling text null; section_ordinal integer null; timestamps. Index `corrections(work_id)`. Changeset: cast [work_id, kind, about, ruling, section_ordinal]; required [work_id, kind, about]; kind in `misread ruling`; about length max 1000; ruling length max 1000. Meaning: `misread` = a fact the reader got wrong (never assert again); `ruling` = the writer decided (may be raised again only where the same pattern appears somewhere new, saying the ruling out loud).

### 1.8 `revisions`

id; work_id FK CASCADE NOT NULL; section_id FK sections ON DELETE SET NULL null; section_ordinal integer null; seq integer NOT NULL; before text NOT NULL; after text NOT NULL; origin varchar(255) NOT NULL default `'edit'`; note varchar(255) null; timestamps. Indexes: `revisions(work_id)`, UNIQUE `revisions(work_id, seq)`. Changeset: cast [work_id, section_id, section_ordinal, seq, before, after, origin, note]; required [work_id, seq, before, after, origin]; origin in `edit rewrite summary`; unique_constraint [work_id, seq]. Invariant: baseline_body + revisions in seq order (each `String.replace(body, before, after, global: false)`) reproduces `works.body`.

### 1.9 `work_attachments`

id; work_id FK CASCADE NOT NULL; name varchar(255) NOT NULL; kind varchar(255) NOT NULL default `'text'`; content text NOT NULL; byte_size integer NOT NULL default 0; timestamps. UNIQUE `work_attachments(work_id, name)`.

`Attachment.changeset`: cast [work_id, name, kind, content]; required [work_id, name, content]; `put_kind`: if kind (default "text") is `"text"`, promote to `"diff"` when `String.trim_leading(content)` starts with `diff --git`, or name ends with `.patch` or `.diff`; any other kind value is left alone; then validate_inclusion kind in `diff text`; `put_size`: byte_size = UTF-8 byte length of content; unique_constraint [work_id, name]. (Nothing in the in-scope code reads attachments except `Diffs`, which receives the patch text from callers.)

### 1.10 `document_summaries`

id; work_id FK CASCADE NOT NULL; summary text; throughline text; movements jsonb[] (`{:array, :map}`, Postgres array of jsonb/map, default `[]`); guidelines same; tensions same; fingerprint varchar(255); dropped text[] default `{}`; timestamps. UNIQUE `document_summaries(work_id)`. Changeset: cast [work_id, summary, throughline, movements, guidelines, tensions, fingerprint, dropped]; required [work_id]; unique_constraint work_id. One row per work; written with `Repo.insert_or_update`.

Item shapes (string-keyed maps): movement `{"heading","sections":[int],"does"}`; guideline `{"guideline","because","sections":[int]}`; tension `{"tension","sections":[int]}`.

### 1.11 Tables referenced but out of scope

`links` (id, a_work_id, b_work_id, status default pending [pending linking linked failed], summary text, error varchar(255); unique (a_work_id,b_work_id); check a<>b; the pair is stored lowest id first), `link_edges` (link_id, from_id, to_id, edge_type, rationale, ordinal; unique (link_id,from_id,to_id,edge_type)), `folders`, `cuts`, `stack_steps`, `stack_stories`, `users`. `Recovery` and `Linker` touch `links`; their contract is described in the relevant sections.

### 1.12 Cascades summary

Deleting a work cascades to sections, nodes, edges, conversations (and their messages), graph_events, corrections, revisions, work_attachments, document_summaries, links and link_edges. Deleting a draft that others derive from sets their `derived_from_id` to NULL (the condensation survives). Deleting a section sets `revisions.section_id` NULL and cascades its nodes and conversations.

---

## 2. Pure text algorithms

These are the bits that must match exactly: every quote in the system is a literal substring of section text produced by these functions.

### 2.1 `Works.Upload` (upload rules)

```
max_words = 120_000
prepare(title, body, intent) -> {:ok, %{"title","body","intent"}} | {:error, :empty} | {:error, {:too_long, n}}
  body = body || ""
  n = word_count(body)
  n == 0        -> {:error, :empty}
  n > 120000    -> {:error, {:too_long, n}}
  else {:ok, %{"title" => blank(title) || "Untitled draft", "body" => body (UNTRIMMED), "intent" => blank(intent)}}
blank(nil) = nil; blank(s) = trim(s) or nil if empty    # String.trim = Unicode whitespace
too_long_message(n) = "That's #{commas(n)} words, and the limit is #{commas(120000)} for now. Split it and upload the first part."
commas(n): thousands separators, "120,000"
```
`commas`: integer to string, reverse, `replace(~r/(\d{3})(?=\d)/, "\\1,")`, reverse.

### 2.2 `Reading.split(body)`: top-level markdown blocks

`split(nil) = []`. Otherwise iterate `String.split(body, "\n")` with state (blocks, current_lines, fence):
- if `fence` is set and `trim_leading(line)` starts with `fence` (the exact opener string, e.g. "```" or "~~~~"): append the line to current, flush the block (current reversed), fence = nil.
- elif fence set: append line.
- elif `fence_opener(line)` (regex `^\s*(`{3,}|~{3,})` -> captured run) is non-nil: flush the previous current as a block, start a new current = [line], fence = opener.
- elif `String.trim(line) == ""`: flush current, current = [].
- else append line.
At the end flush. Each block = lines joined with "\n", then `trim_trailing`, drop blocks that are blank. (Leading indentation of the first line is preserved.) A closing fence only needs to START with the opener string, so a closer may be longer than the opener. An unclosed fence swallows the rest of the document into one block.

Examples (tests): `split("One.\nTwo.\n\nThree.\nFour.") == ["One.\nTwo.", "Three.\nFour."]`; a fenced block with blank lines inside is one block starting with "```" and containing "end\n```".

### 2.3 `Works.Sentences.reflow/1`: one sentence per line

`reflow(nil) = nil`, `reflow("") = ""`. Otherwise `Reading.split(text) |> map reflow_block |> join "\n\n"` (so whitespace-only input -> ""). Idempotent.

`reflow_block(block)`:
1. If not `prose?(block)`: return block unchanged.
2. If `quoted?(block)` (regex `^\s*>`): strip the prefix `^\s*>\s?` from EVERY line, join with "\n", run the whole `reflow/1` on that (so bare `>` lines become paragraph breaks), split on "\n", map each line: `""` -> `">"`, else `"> " <> line`, join "\n".
3. Else: `String.split(block, ~r/\s*\n\s*/)` joined with " ", collapse `[ \t]+` to one space, trim, then `split_sentences`.

`split_sentences(joined)`:
- `@boundary = ~r/([.!?]["'”’)\]]*)\s+(?=["'“‘(\[*_`]*(?:\p{Lu}|\d))/u` ; replace every match with `\1` + "\n" (captured punctuation+closers, then newline; the whitespace is consumed).
- split on "\n"; fold left: for each line, if the accumulated previous line matches `@abbrev` then join it to this line with a single space, else start a new line.
- `@abbrev = ~r/(?:^|\s)(?:e\.g|i\.e|vs|etc|cf|viz|ca|Mr|Mrs|Ms|Dr|Prof|St|No|Fig|Jr|Sr|Inc|Ltd|Co|[A-Z])\.["'”’)\]]*$/u` (tested against the previous line, anchored at its end; note single capital letters are all treated as initials; abbreviations are case-sensitive).
- join with "\n".

`prose?(block)` is false (block left alone) if ANY of these hold, tested in this order (first = first line of block with leading whitespace stripped; second = trimmed second line or ""):
1. `second` matches `^(=+|-+)$` (setext underline).
2. `second` matches `^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$` (table delimiter row).
3. first matches `^(`{3,}|~{3,})` (fence).
4. first matches `^\#{1,6}\s` (ATX heading).
5. block matches `^(\s{4,}|\t)` (indented code).
6. first matches `^[-*+]\s|^\d+[.)]\s` (list item).
7. first matches `^<[a-zA-Z!\/]` (html).
8. whole block matches `^!?\[[^\]]*\]\([^)]*\)\s*$` (lone image/link).
9. first matches `^(-{3,}|\*{3,}|_{3,})\s*$` (thematic break).
10. every line, leading-whitespace-stripped, starts with `|` (table with pipes).
Otherwise prose.

Examples from `sentences_test.exs` (input -> output):
- `"At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\nreset for lock delay. The idea came from agent-8, which had not committed the\ncode. Agent-8 had logged a decision."` -> three lines: `"...Guideline step reset for lock delay."`, `"The idea came from agent-8, which had not committed the code."`, `"Agent-8 had logged a decision."`.
- `"One. Two.\n\nThree. Four."` -> `"One.\nTwo.\n\nThree.\nFour."`.
- `"Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done."` -> `"Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone."`.
- `"The file is game.js and it runs. agent-8 logged it. Then it ran."` -> `"The file is game.js and it runs. agent-8 logged it.\nThen it ran."` (lowercase start is not a boundary).
- `~s(It scored 3.16 on the board! Was that enough? "No," she said. "Not nearly." Fine.)` -> lines `It scored 3.16 on the board!` / `Was that enough?` / `"No," she said.` / `"Not nearly."` / `Fine.`
- `"This is bold. **Really** bold. \`Code\` too. \`code\` is not a start."` -> `"This is bold.\n**Really** bold.\n\`Code\` too. \`code\` is not a start."`
- `"He said “stop.” Then he left (for good.) Fine [really.] Done."` -> `He said “stop.”` / `Then he left (for good.)` / `Fine [really.]` / `Done.`
- `"Wait... What? Wait... and then. End."` -> `Wait...` / `What?` / `Wait... and then.` / `End.`
- `"Élan vital. Über alles. Ça va."` -> three lines.
- `"See Fig. 3 and cf. the table. Mrs. Smith vs. Mr. Jones, Inc. won. Prof. Lee agreed."` -> `See Fig. 3 and cf. the table.` / `Mrs. Smith vs. Mr. Jones, Inc. won.` / `Prof. Lee agreed.`
- `"One   sentence,\t\tspaced.\n   Another,\n\t indented. "` -> `"One sentence, spaced.\nAnother, indented."`
- `"One. Two\r\nthree.\r\n\r\nFour."` -> `"One.\nTwo three.\n\nFour."` (CRLF: `Reading.split` splits on "\n", the `\r` left on lines is eaten by `\s*\n\s*`/trim; blank-line detection uses `String.trim`).
- `"> First. Second.\n>\n> Third. Fourth."` -> `"> First.\n> Second.\n>\n> Third.\n> Fourth."`
- Unchanged blocks: `"## A heading. With a period. And More."`; table `"| a. B | c. D |\n|---|---|\n| e. F | g. H |"`; `"- one. Two.\n- three. Four."`; `"1. first. Second.\n2. third. Fourth."`; `"    code. More code.\n    still code. Yes."`; `"---"`; `"<div class=\"x\">one. Two.\nthree.</div>"`; `"A title. With a period.\n====="`; `"Sub. Title.\n---"`; `"a. B | c. D\n---|---\ne. F | g. H"`; tilde fenced block; `"![alt text. More.](img.png)"`; fenced code with blank lines inside.
- Mixed doc: `"# Title\n\nIntro one. Intro two.\n\n- item one. Still one.\n- item two.\n\n\`\`\`\ncode. Code.\n\`\`\`\n\n> Quoted one. Quoted two.\n\nOutro one. Outro\ntwo."` -> only the intro, the quote and the outro are split.

### 2.4 `Works.Segmenter.split(text)`

Returns `[%{title, body}]`; `split(non-string) = []`. Constants: `target_words = 1800`, `min_words = 250`, `max_words = 4000`.

`normalize(text)`: replace "\r\n" with "\n", then "\r" with "\n", then `\n{3,}` -> "\n\n", then `String.trim` (Unicode whitespace).

Strategy (first that yields a non-nil result):
1. `text == ""` -> `[]`.
2. `by_markdown`: lines = split on "\n"; `heads` = number of lines matching `^\#{1,3}\s+\S`. If `heads >= 2`: `chunk_on(lines, is_heading, title_of)` where title = line with `^#+\s*` removed, trimmed. -> `finish`.  (Counted even inside code fences: a `# comment` line in a fenced block counts and splits.) Note: headings of depth 4+ (`####`) are NOT section boundaries; they stay in the body.
3. `by_marker`: a line is a marker if `String.length(String.trim(line)) < 90` and matches `@marker`. If at least 2 marker lines: chunk_on markers with title = `String.trim(line)` -> `finish`.
   `@marker = ~r/^\s*(?:(?:chapter|part|book|act|section)\s+(?:[0-9]+|[ivxlc]+|[a-z]+)|[ivxlc]{1,7}\.|\*\s*\*\s*\*|—{3,}|-{3,})\s*[:.\-—]?\s*(.{0,80})$/i` (NO `u` flag, case-insensitive). Verified behaviour: matches `Chapter 1`, `chapter one: The Start`, `IV.`, `I.`, `x.`, `ill.`, `Part Two — The Sea`, `* * *`, `***`, `---`, `----`, `Section a`, `Act III`, `Book 2.`, `Chapter 12: ünïcode title`; does NOT match `Chapter` alone, `mild.`, `———`, `— — —`, `—`, or a line whose tail exceeds 80 BYTES (a `Chapter 1 ` + 60 two-byte chars fails). The `—{3,}` alternative is dead: without `u` the pattern is bytes, the quantifier binds the last byte of the three-byte em dash, so a run of real em dashes never matches. Also `part|book|act|section` followed by ANY lowercase word matches, e.g. "Part of the road" (short lines starting "Section three of..." count) - harmless unless two such lines exist.
4. `by_windows` (fallback).

`chunk_on(lines, is_head?, title_of)`: scan lines; on a heading line, close the current chunk (if any) and start `{title: title_of(line), lines: []}`; the heading line itself is NOT kept in the body. A non-heading line before any heading starts a chunk titled `"Opening"` containing that line. After the scan the current chunk is closed. Each chunk -> `title = blank_to_untitled(title)` (`""` -> `"Untitled"`, else `String.slice(title, 0, 120)`), `body = lines joined "\n" then String.trim`. Consequence: heading and marker lines vanish from section bodies and therefore from `works.body` (the body is later rebuilt as the join of section bodies).

`by_windows(text)`: `window(text)` -> list of bodies; for each (index i from 1): `body = Sentences.reflow(body)`, `title = derive_title(body, i)`; then `finish`.

`window(text)`: split on `\n\s*\n` (trim: true); fold over paragraphs (each `String.trim`med, word count w): if the head window exists and its words < 1800, append the paragraph to the head window (words += w); else start a new window. Result windows' paragraphs joined by "\n\n". So a window can exceed 1800 by up to one paragraph; a single oversize paragraph is its own window and is never cut.

`derive_title(body, i)`: first = first line of body (split "\n", parts 2), with `^\#{1,6}\s+` removed, all `[*_`]+` removed, trimmed, sliced to 60 graphemes; if `String.length(first) > 12` then `"#{i}. #{first}…"` (… is U+2026, appended after the 60-char slice) else `"Section #{i}"`.

`finish(chunks)`:
1. Reject chunks whose body is blank.
2. Left fold building a reversed list: for each chunk, if there is a previous chunk and `word_count(chunk.body) < 250` and `word_count(prev.body) < 1800`, merge: `prev.body <> "\n\n" <> chunk.body` (prev title kept); else push. (Only the chunk being added is tested for being a runt; a runt FIRST chunk stays.)
3. `flat_map subdivide`.
4. `[]` -> nil else the list.

`subdivide(chunk)`: if `word_count(body) <= 4000` keep. Else `parts = window(body)`; if fewer than 2 parts keep the chunk whole (a single huge paragraph); else titles `"#{title} (#{i}/#{n})"` (i from 1).

After the strategy: every chunk's body is passed through `Sentences.reflow` (idempotent; done after splitting so a chapter marker line is not folded into the paragraph).

Examples (segmenter_test): a no-structure 4x(40-word) post -> 1 section; three `# X` headings with 300 words each -> titles `["The Opening","The Middle","The End"]`; two `Chapter N` markers -> 2 sections, first title contains "Chapter 1"; prose before the first marker is kept in an "Opening" section; a 400-word `# Big` followed by `# Tiny\ntwo words` -> ONE section (runt folded; body contains "two words"); `# Argument` with 6000 words over 20 paragraphs plus `## Rebuttal` (300 words) -> sections titled `Argument (1/n)`..., and `Rebuttal`, every part <= 4000 words; one 6000-word paragraph after `# Wall` -> single section; a body `**JUSTICE GORSUCH:** Counsel, what is the limiting principle here?\n\n` + 400 words, with no headings -> title contains `JUSTICE GORSUCH: Counsel`, no `*`; `# Chatrie v. United States — Argument\n\n` + 400 words: ONE heading only so `by_markdown` is skipped, windows strategy runs and the title is derived from the first line with `#` stripped (`1. Chatrie v. United States — Argument…`); `split("") == split("   \n\n  ") == split(nil) == []`; reflow integration: `"First sentence of the opening. Second one,\nwrapped by an editor. Third.\n\n\`\`\`\nx = 1. y = 2.\n\`\`\`\n\nLast paragraph. Done."` -> one section whose body is `"First sentence of the opening.\nSecond one, wrapped by an editor.\nThird.\n\n\`\`\`\nx = 1. y = 2.\n\`\`\`\n\nLast paragraph.\nDone."`.

### 2.5 `Works.Reflow`: PDF text paragraphs

Used by importers (outside this scope's callers) but defined here.

- `wrapped?(text)`: non-empty lines (trimmed non-blank) count >= 12 and `blanks <= div(lines, 12)` where `blanks = length(String.split(text, ~r/\n\s*\n/)) - 1`. Non-binary -> false.
- `reflow(text)`: `wrapped?` ? `do_reflow` : text.
- `do_reflow`: `keep = intact_hyphens(text)` (set of lowercased matches of `[\p{L}\p{N}’']+-[\p{L}\p{N}’']+` /u in the ORIGINAL text: hyphenated words that appear intact on one line). lines = text with CRLF->LF split on "\n", each `String.trim`med, drop furniture lines, drop empty. `measure` = the length (graphemes) at sorted index `div(count*2, 3)` of the line-length list (it is the 2/3 percentile, not the median, despite the comment; empty -> 0). `chunk_paragraphs(lines, measure)`, each paragraph joined by `join(lines, keep)`, drop empties, join with "\n\n".
- `furniture?(line)`: matches any of `^Cite as:`, `^Opinion of the Court$`, `^Syllabus$`, `^Per Curiam$`, `^(?:[A-Z]+, )+(?:C\. )?J\.,\s+(?:concurring|dissenting)`, `^\d{1,3}$`; OR `caption?`: strip `^\d{1,3}\s+` and `\s+\d{1,3}$`, take letters (`\p{L}`), require count >= 8 and uppercase letters (`c == String.upcase(c)`) / count >= 0.75.
- `chunk_paragraphs`: fold lines with (done, current): if `heading?(line)` (regex `^\#{1,6}\s+\S`, or `^[IVXL]{1,5}$`, or `^[A-Z]$`): push current paragraph then `[line]` as its own paragraph; elif `String.length(line) < measure * 0.78`: current + line closes the paragraph; else append to current. At the end, the final current is a paragraph. Empty paragraphs dropped.
- `join(lines, keep)`: fold; first line as is; if accumulated text ends with "-" then `mend(acc, line, keep)`; else `acc <> " " <> line`. Finally trim.
- `mend(acc, line, keep)`: `stem` = last whitespace-separated token of `acc` with trailing "-" trimmed; `head` = first token of `line`; `word = downcase(stem <> "-" <> strip_punct(head))` where `strip_punct` removes trailing chars outside `[\p{L}\p{N}'’-]`; if `word` in keep: `acc <> line` (keep hyphen, no space) else `trim_trailing(acc, "-") <> line` (hyphen removed, words joined).
- `align(quote, source)`: for a quote spanning a mended hyphen: split quote lines, trim, drop empties, `join(lines, intact_hyphens(source))`. Non-binary source -> quote unchanged.
Test: the Landor sample reflows into >= 4 paragraphs, first starts "JUSTICE GORSUCH", contains "private capacities for damages." on one line, the running head "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND" and "PUBLIC SAFETY" are dropped, `"I"` stands alone as a paragraph; `for-\ncause` is kept as `for-cause` because `for-cause` appears intact elsewhere; `align("sue nonconsenting state employees in their private capaci-\nties for damages.", @page)` verifies in the reflowed text.

### 2.6 `Analysis.Anchor`: verbatim quote verification

`@min_chars = 8`.

`verify(quote, source)` -> `{:ok, source_span}` | `:error`:
- nil quote or nil source -> `:error`; non-binaries -> `:error`.
- `quote = String.trim(quote)`; if `String.length(quote) < 8` -> `:error`.
- `{norm_source, index} = normalize_indexed(source)`; `norm_quote = normalize(quote)` (same function, index discarded).
- Find the first occurrence of `norm_quote` in `norm_source` (byte-wise substring search). None -> `:error`.
- Else map the match's [start char, end char] back through `index` (a list: for each normalised grapheme, the index of the original grapheme it came from) and return `String.slice(source, start, stop - start + 1)` where `start = index[from]`, `stop = index[to] || start`; if indexes are not integers or stop < start return `""` (callers treat empty as failure).

`normalize_indexed(text)`: iterate `String.graphemes(text)` with a `prev_space?` flag initially TRUE:
- if the grapheme is whitespace (`" ", "\n", "\r", "\t", U+00A0, U+200B` exactly; note the grapheme `"\r\n"` is a single grapheme and is NOT in this set, so it is kept as a non-space character): emit a single `" "` (mapped to this grapheme's index) unless `prev_space?` already true (collapse; leading whitespace is dropped); set prev_space? true.
- else `folded = fold(g)`; emit `folded`, append `String.length(folded)` copies of the index to the index list; prev_space? false.
`fold`: `‘ ’ ‛` -> `'`; `“ ”` -> `"`; `– —` -> `-`; `…` -> `...`; anything else -> `String.downcase(g)`.
A trailing whitespace in the source becomes one trailing " " in `norm_source` (harmless). So: matching is case-insensitive, whitespace-run-insensitive, curly-quote/dash/ellipsis-insensitive, and nothing else; no fuzzy matching (order, dropped negations, substituted words all fail).

Position conversion detail: `:binary.match` returns a byte position in `norm_source`; it is converted to a grapheme position with `String.length(binary_part(norm_source, 0, byte_pos))`; `to = char_pos(pos+len) - 1`.

`filter(nodes, source)` -> `{kept, discarded_count}`: for each node map take `node[:quote] || node["quote"]`; if `verify` gives `{:ok, q}` with `byte_size(q) > 0`, the kept node is `Map.put(node, :quote, q)` (quote replaced by the source's own wording); else discarded. Order preserved.

Examples (anchor_test): source `She had been standing at the window for an hour before anyone noticed, and by then the\nlight had gone completely. "You can't keep doing this," her brother said, from the doorway.\nHe did not come in.\n`:
- `verify("standing at the window for an hour", s)` -> `{:ok, "standing at the window for an hour"}`.
- `verify("“You can’t keep doing this,” her brother said", s)` -> ok.
- `"She turned and left without saying anything at all"` -> error; `"the"` -> error (< 8).
- para `"She kept them in the freezer, which she never explained to anyone, and by then it hardly mattered."`: `"the freezer she kept them in which she never explained"` -> error; `"which she explained to anyone, and by then it hardly mattered"` -> error; `"had been standing at window for an hour before anyone noticed"` -> error; `"standing at the doorway for an hour"` -> error.
- wrapped `"She kept them in the\nfreezer, which she never\nexplained to anyone."` with quote `"She kept them in the freezer, which she never explained"` -> ok, span is a substring of the wrapped text (newlines preserved in the span).
- `filter([%{title: "real", quote: "He did not come in."}, %{title: "invented", quote: "She screamed at the top of her lungs and ran."}, %{title: "also real", quote: "by then the light had gone completely"}], source)` -> `{[real, also real], 1}`; a nil quote -> `{[], 1}`.
- Sentences-per-line interplay: `verify("went cold on the counter. Nobody moved", body)` returns `"went cold on the counter.\nNobody moved"` (the stored span keeps the newline).
- `verify("1. The purpose of society", "1. The purpose of society is ...")` ok; `verify("The  purpose\nof society", ...)` ok; `"society of purpose the"` error.

### 2.7 `Selection`: where a rendered selection lives in the draft

`@min_chars = 12`. `squash(text)` = replace `\s+` (u flag, Unicode whitespace) with one space, trim.

`locate(work, text)` -> `{:ok, %{section, block, span}}` | `:error`:
- non-binary text -> `:error`; `String.length(squash(text)) < 12` -> `:error`.
- For sections in ordinal order (`Works.list_sections`): `blocks = Reading.split(section.body)`; first block for which `in_block(block, text)` is non-nil gives `{block, span}`; if none, try the whole section: `in_block(section.body, text)` giving `block = section.body`. The first section that matches wins.

`in_block(block, needle)` -> source substring or nil:
1. `{source_dense, source_at} = dense(block)`: graphemes of block with every grapheme matching `~r/\s/u` removed; `source_at` = original grapheme index of each kept grapheme.
2. `plain = rendered_text(block)`; `{plain_dense, _} = dense(plain)`; `{needle_dense, _} = dense(needle)`.
3. Byte-wise exact (case-sensitive) search of `needle_dense` in `plain_dense`. No match -> nil.
4. `map = alignment(source_dense, plain_dense)`; `from = map[char_index(plain_dense, pos)]`; `to = map[char_index(plain_dense, pos+len) - 1]` (char_index = grapheme count of the first `n` bytes).
5. `span`: `a = source_at[from]`, `b = source_at[to]`; require both integers and `b >= a`; return `String.slice(block, a, b - a + 1)` (graphemes), else nil.

`alignment(source_dense, plain_dense)`: src = graphemes of source_dense (array). For each grapheme `g` of plain_dense in order, with a cursor `i` (start 0): search `j` from `i` up to `min(n-1, i+400)` inclusive for `src[j] == g`; if found, emit `j` and set `i = j+1`; if not found, emit `min(i, max(n-1,0))` and leave `i` unchanged (the renderer invented a character; skip it). If src is empty every search returns nil.

`rendered_text(source)`: `Markdown.to_html(source)` (default options, hard breaks), take the HTML string; delete `<script...>...</script>` and `<style...>...</style>` (regex `<(script|style)\b[^>]*>.*?<\/\1>` with dotall); replace every `<[^>]+>` with a single space; then unescape exactly these entities in this order: `&lt;`->`<`, `&gt;`->`>`, `&quot;`->`"`, `&#39;`->`'`, `&amp;`->`&`. The exact HTML does not matter to correctness: any renderer whose visible text is the source text minus markdown syntax (plus a few invented characters like footnote `↩`) works, because `alignment` is a bounded subsequence walk. A Temper port needs a markdown-to-visible-text function, not a full HTML writer.

Tests (`selection_test.exs`): round trips for links, code spans, numbered lists, bullets, blockquotes, tables, headings, entities, nested emphasis, images, fenced code: pick the middle words of the rendered text, `in_block` returns a literal substring of the source containing the first three selected words. `locate` on a draft with a link `[window](https://x.test)` returns a span containing `[window](https://x.test)` and section ordinal 1; a selection spanning a paragraph break into a numbered list still lands; unknown text and `"the"` give `:error`.

### 2.8 `Diff`: paragraph LCS with word diff inside

- `paragraphs(nil) = []`; else CRLF->LF, split on `\n{2,}` (trim: true), each `String.trim`med, blanks dropped.
- `key(p)` = collapse `\s+` to one space, trim (identity for alignment; a re-wrap is not an edit).
- `rows(before, after)`: `a = paragraphs(before)`, `b = paragraphs(after)`; LCS op list from `lcs`, then `pair`.
- `lcs`: dynamic programming table over keys (`table[i][j]` = LCS length of a[i..], b[j..]; 0 at i==n or j==m; if `key(a[i]) == key(b[j])` then `1 + table[i+1][j+1]` else `max(table[i+1][j], table[i][j+1])`). Walk from (0,0): if both in range and keys equal -> `{:same, a[i]}`, i+1,j+1; elif `j < m` and (`i >= n` or `table[i][j+1] >= table[i+1][j]`) -> `{:ins, b[j]}`, j+1 (ties prefer insertion first); else `{:del, a[i]}`, i+1.
- `pair(ops)`: `{:same, p}` -> row `{:same, p, p}` (the BEFORE text is on both sides); a maximal run of non-same ops is split into `dels` (in order) and `ins` (in order); zip-longest the two lists: `(l, r)` both present -> `{:change, l, r}`; only ins -> `{:ins, r}`; only del -> `{:del, l}`. Rows emitted in zip order.
- `words(l, r) = Rewrite.diff(l, r)`.
- `stat(rows)` -> `%{same, changed, added, removed}` counts of `:same`/`:change`/`:ins`/`:del`.
- `any?(rows)` = any row not `:same`.
Examples: `rows("One.\n\nTwo.\n\nThree.", "One.\n\nTwo, amended.\n\nThree.")` -> `[{:same,"One.","One."},{:change,"Two.","Two, amended."},{:same,..}]`; insertion in the middle -> `[:same, {:ins,"INSERTED."}, :same]` with stat `%{same: 2, changed: 0, added: 1, removed: 0}`; `["A.","B.","C."]` vs `["A1.","B1.","C1."]` -> three `:change`; `["A."]` vs `["A1.","B.","C."]` -> one `:change` and two `:ins`; `rows("", "") == []`, `rows(nil, nil) == []`; `"A sentence that\nwraps across lines."` vs `"A sentence that wraps   across lines."` -> one `:same`.

### 2.9 `Rewrite.diff/2`: word-level diff

`words(nil) = []`; else tokens = every match of `\S+\s*` (word plus trailing whitespace; leading whitespace of the text is dropped). Two tokens are equal when their trimmed forms are equal. Build an LCS table bottom-up. Walk from (0,0): equal -> `{:same, b_token}` (the NEW text's token including its whitespace); elif `table[i][j+1] >= table[i+1][j]` -> `{:ins, b[j]}`; else `{:del, a[i]}`; when one side is exhausted emit the remaining tokens as `:ins`/`:del`. Both empty -> `[]`. Finally consecutive ops of the same kind are merged by concatenating their text. Returns `[{:same | :del | :ins, text}]`.
Examples: `diff("a b c","a b c") == [{:same,"a b c"}]`; `diff("", "new text") == [{:ins,"new text"}]`; `diff("the cat sat on the mat","the dog sat on the mat")` contains a `:same` containing `"sat on the mat"`, a `:del` containing `cat`, an `:ins` containing `dog`; concatenating non-ins parts reproduces `a` and non-del parts reproduce `b` (for tokens whose trailing whitespace matches).

### 2.10 Small text helpers

- `Reading.plain(nil) = ""`; else: replace `\[([^\]]*)\]\([^)]*\)` with `\1`; delete `[`*_~]`; delete `^#+\s*` (multiline: each line start); collapse `\s+` to " "; trim. (Quote as it reads on the page.)
- `Reading.heading?(text)` = matches `^\#{1,6}\s+\S`; `heading_level` = count of leading `#` (1 if none); `heading_text` = remove `^\#+\s*`, trim.
- `Reading.outline(page)` (page = list from `Reading.page`): for each section entry produce `%{id: "sec-#{ordinal}", level: 0, title: section.title, words: section.word_count}`, followed by one entry per block whose `text` is a heading: `%{id: "block-#{ref}", level: heading_level, title: heading_text, words: nil}`, EXCLUDING headings whose lowercased title equals the lowercased section title. `outline(non-list) = []`.
- `Works.search`/`Chat.search` tokenisation: `String.downcase`, split on `[^a-z0-9']+` (trim), drop terms shorter than 3 characters.
- Slug: 16 random bytes, base64url, no padding (22 chars).
- `Rewrite.span_label(span)`: word count 0 (or nil / non-binary) -> `"Rewrites"`; < 25 -> `"Rewrites of one line"`; else `"Rewrites of #{n} words"`.
- `Rewrite.span_extent(span)`: flat = collapse `\s+` to " " and trim; `nil` if empty or `String.length(flat) <= 120`; else `slice(flat, 0, 64) <> " … " <> slice(flat, -48, 48)` (the middle is U+2026 with single spaces on both sides). Non-binary -> nil.
- `Rewrite.answer_budget(span) = max(3000, word_count(span) * 7)`.
- `Rewrite.steer_block(steer)`: nil, "" or whitespace-only -> `""`; else trim, slice to 400 graphemes (`max_steer_chars = 400`) and produce (template below, section 4.5).
- `Summary.spine(siblings, section)`: lines `"#{ordinal}. #{title}"` with suffix `"  <- THIS ONE"` on the section whose ordinal equals `section.ordinal`, joined by "\n".
- `Summary.previous_block(siblings, section)`: find the sibling with ordinal `here - 1`; if it has a non-empty summary: `"\nThe section before this one (#{prev.ordinal}. #{prev.title}) was summarised as:\n#{summary}\n"` else `""`.
- `Graph` DOT escape: `\` -> `\\`, `"` -> `\"`, "\n" -> " ", slice to 90 graphemes.

---

## 3. Markdown

`Marginalia.Markdown.to_html(text, opts \\ [])` returns a safe HTML string (in Phoenix a `{:safe, iodata}`; Temper can return a string).

- `nil` or `""` -> empty safe string. Non-binary -> HTML-escaped `to_string(other)`. On any parser error or exception -> HTML-escaped plain text of the input (never raises).
- Parser: MDEx 0.13.5 (comrak, CommonMark with GFM extensions) called as `MDEx.to_html(text, opts)` with exactly:
  - `extension: [strikethrough: true, table: true, autolink: true, tasklist: true, footnotes: true]`
  - `parse: [smart: false]` (no smart quotes/dashes)
  - `render: [hardbreaks: (breaks == :hard), unsafe: false]` where `breaks:` option defaults to `:hard`; `Reading` uses `breaks: :soft`.
  - `sanitize: MDEx.Document.default_sanitize_options()` (ammonia defaults, below).
  - No `syntax_highlight` key is passed, and the observed output has no highlighting: fenced code renders as plain `<pre><code class="language-xxx">`.
- Hard vs soft breaks: hard -> each source newline in a paragraph becomes `<br>\n`; soft -> newline stays a literal "\n" in the paragraph text (`<p>One.\nTwo.</p>`).
- Sanitizer (ammonia defaults): allowed tags `a abbr acronym area article aside b bdi bdo blockquote br caption center cite code col colgroup data dd del details dfn div dl dt em figcaption figure footer h1 h2 h3 h4 h5 h6 header hgroup hr i img ins kbd li map mark nav ol p pre q rp rt rtc ruby s samp small span strike strong sub summary sup table tbody td th thead time tr tt u ul var wbr`; `script` and `style` contents removed; allowed attributes include `a: href hreflang`, `img: align alt height src width`, `code: class translate tabindex`, `pre: class style`, `span/div: class style data-line`, `ol: start`, table cell attributes; all links get `rel="noopener noreferrer"`; `<input>` (task-list checkboxes) is stripped. Inline raw HTML is not emitted (unsafe false): observed `<script>alert(1)</script>` -> text `alert(1)` and `<b onclick=x>b</b>` -> `b`.

Observed outputs (run on this machine with the exact options):
- `"one\ntwo"` (hard) -> `<p>one<br>\ntwo</p>`
- `"One.\nTwo.\n\nThree."` (soft) -> `<p>One.\nTwo.</p>\n<p>Three.</p>`
- ```` ```elixir\ndef a do\n  1\nend\n``` ```` -> `<pre><code class="language-elixir">def a do\n  1\nend\n</code></pre>`
- plain fence -> `<pre><code>plain\n</code></pre>`
- `# Head\n\n![alt](/i.png)\n\n> quote\n\n1. a\n2. b` -> `<h1>Head</h1>\n<p><img src="/i.png" alt="alt"></p>\n<blockquote>\n<p>quote</p>\n</blockquote>\n<ol>\n<li>a</li>\n<li>b</li>\n</ol>`
- task list `- [ ] a` -> `<ul>\n<li> a</li>\n...` (checkbox stripped, a leading space remains)
- table -> `<table>\n<thead>\n<tr>\n<th>a</th>...</tr>\n</thead>\n<tbody>...</tbody>\n</table>`
- `~~gone~~` -> `<del>gone</del>`; bare `http://x.com` -> `<a href="http://x.com" rel="noopener noreferrer">http://x.com</a>`
- footnote `text[^1]` + `[^1]: note` -> `text<sup><a href="#fn-1" rel="noopener noreferrer">1</a></sup>` then `<ol>\n<li>\n<p>note <a href="#fnref-1" rel="noopener noreferrer">↩</a></p>\n</li>\n</ol>`
- Private-use characters U+E000..U+E005 pass through the renderer and sanitizer untouched (this is what `Reading.render_block` depends on).

Where Markdown is used: `Reading.render_block` (draft pages, soft breaks), `Selection.rendered_text` (default hard breaks; only its text matters), and chat replies in the web layer (hard breaks).

`Reading.render_block(text, mark, ref, preview \\ nil)` returns safe HTML:
1. With `preview = %{original: o, text: t}` (both binaries) and `o` found byte-wise in `text`: replace that occurrence by `Rewrite.diff(o, t)` rendered as: `:same` text as is, `:del` wrapped in U+E004/U+E005, `:ins` wrapped in U+E002/U+E003; render the whole string (no mark) as markdown (soft breaks); then replace U+E002 -> `<ins class="mg-swap">`, U+E003 -> `</ins>`, U+E004 -> `<del class="mg-cut">`, U+E005 -> `</del>`. If `o` is not found, fall through to the no-preview path.
2. Otherwise `render_markdown(text, mark, ref)`: if `mark` is non-nil and found byte-wise in `text` at `(pos, len)`: first `inside_delimiters`: shrink the span while its first byte is one of `* _ ` ~` (left) and then while its last byte is one of those (right); wrap the (shrunk) span in U+E000/U+E001; render as markdown with `breaks: :soft`; replace U+E000 -> `<mark id="anchor-#{ref}">`, U+E001 -> `</mark>`. A mark made only of delimiters yields an empty `<mark>` pair (does not crash).
Examples: `render_block("Three.\nFour.", "Four.", 2)` contains `<mark id="anchor-2">Four.</mark>` and no `<br`; `render_block("Prudence. **We must slow the pace. Progress will still seem fast.** Two things.", "**We must slow the pace. Progress will still seem fast.**", "r1")` contains no `**`, contains `<strong>` and `<mark id="anchor-r1">We must slow the pace.`; `"Before *the marked words* after."` with quote `*the marked words*` -> `<em>` and a `<mark`; `"This is *very\nimportant* indeed."` -> `<em>very\nimportant</em>`.

---

## 4. Public functions, module by module

Notation: `R` = reads table, `W` = writes table. "Owner-scoped" = the query includes `user_id`. Return shapes are Elixir terms: `{:ok, x}`, `{:error, e}`, `nil`, maps with atom keys.

### 4.1 `Marginalia.Works`

**Works**
- `list_works(user_id)` R works: `where user_id`, `order by id desc`.
- `get_work(user_id, id)` R works: owner-scoped single row or nil. `get_work!` raises `Ecto.NoResultsError`.
- `get_by_slug(slug)` R works: no ownership check (holding the 128-bit slug IS read permission). Non-binary -> nil.
- `public_drafts()` R users, works: if `Accounts.owner()` (the user whose email equals the configured owner email, case-insensitive; nil when no owner email configured) is nil -> `[]`; else that user's works `order by inserted_at desc`.
- `public_draft(slug)`: work with that slug AND `user_id == owner.id`, else nil.
- `owner?(work, user)`: true iff `work.user_id` non-nil and equals `user.id`.
- `change_work/2`: the changeset (section 1.1).
- `create_work(user_id, attrs)` W works, sections: one DB transaction.
  1. Insert `%Work{user_id: user_id}` through `Work.changeset(attrs)`. attrs have STRING keys in the web layer (`"title"`, `"body"`, `"intent"`, optional `"source_url"`, `"derived_from_id"`, ...); atom keys also work. A changeset error rolls back and returns `{:error, %Ecto.Changeset{}}`.
  2. `insert_sections`: `Segmenter.split(work.body)`; none -> `{:error, :no_sections}` (rolled back, returned as `{:error, :no_sections}`). Otherwise one `insert_all` of rows `{work_id, ordinal: i (1-based), title, body, word_count (ASCII word count of the section body), status: "pending", inserted_at, updated_at: now truncated to seconds}`.
  3. Re-read sections in ordinal order, `joined = bodies joined with "\n\n"`, and update the work: `baseline_body = joined`, `body = joined` (via `Ecto.Changeset.change`; `word_count` is NOT recomputed, it stays the count of the raw upload, which still includes heading/marker words that were lifted into titles). This makes `baseline + patches == body` hold from the first moment.
  4. Returns `{:ok, work}` (with the updated body/baseline, slug, id; status "pending").
- `condensation_of(work_id)` R works: the newest (`order by id desc limit 1`) work whose `derived_from_id == work_id`, or nil.
- `update_work(work, attrs)`: `Work.changeset |> Repo.update`.
- `set_status(work, status, detail \\ nil)` W works: sets `status` and `status_detail` (detail replaces the old one, usually nil) with no validation; returns `{:ok, work}`.
- `delete_work(work)`: `Repo.delete` (cascades, section 1.12).

**Sections**
- `list_sections(work_id)`: `order by ordinal asc`.
- `get_section(work_id, ordinal)`: by (work_id, ordinal) or nil.
- `set_section_status(section, status)`: update status only.

**Nodes and edges**
- `list_nodes(work_id, opts)`: opts `type:` (node_type equality) and `section_id:`; `order by ordinal asc, id asc`. NOTE this orders by node ordinal first, so a mixed-type list interleaves by ordinal, not by section.
- `get_node(work_id, id)`: scoped to work.
- `insert_node(attrs)` -> `{:ok, node}` | `{:error, changeset}`.
- `set_node_status(work_id, node_id, status)`: node missing in that work -> `{:error, :not_found}`; else update via `Node.changeset(%{work_id, node_type: existing, title: existing, status})` (so an invalid status gives `{:error, changeset}` with `status is invalid`).
- `insert_nodes(work_id, section_id, attrs_list)`: for each attrs (index i from 0) insert `Node.changeset(attrs + work_id + section_id + ordinal: i if absent)`; a rejected one is logged at warning (`"marginalia: node rejected: #{inspect(errors)}"`) and skipped (its index is consumed). Returns the inserted nodes in order.
- `link(work_id, from_id, to_id, type \\ "leads_to", ordinal \\ 0, rationale \\ nil)`: insert edge with `on_conflict: :nothing` (unique from,to,type).
- `list_edges(work_id)`: `order by ordinal asc, id asc`.
- `counts(work_id)` -> `%{beats, spine, notes, questions, threads, total}` from `group by node_type` (total counts ALL types).
- `search(work_id, query, limit \\ 12)`: terms per section 2.10; none -> `[]`. For each node of the work (all types): `text = downcase("#{title} #{body} #{quote}")` (nil -> empty), `score = number of terms that are substrings of text`; keep score > 0; sort by `{-score, id}`; take `limit`.
- `find_in_source(work_id, phrase, limit \\ 5)`: `needle = trim(downcase(phrase))`; empty -> `[]`. For each section in order: `hay = downcase(section.body)`; first byte-wise occurrence `(pos, len)` of needle; `start = max(pos - 160, 0)`; `window = String.slice(section.body, start, len + 320)` (note: byte offsets from the lowercase text used as grapheme offsets into the original; exact for ASCII, drifts for non-ASCII/case changes that alter byte length). One hit per section: `%{section: title, ordinal: n, window: window}`. Take `limit` hits.
- `connections(work_id, node_id)` -> `{out, into}`: edges of types in `Weave.types()` (develops pays_off requires tension realises asks_about), joined to nodes; `out` = edges with `from_id == node_id`: `%{type, why: rationale, node: <to node>}`; `into` = edges with `to_id == node_id`: `%{type, why, node: <from node>}`; dangling dropped.
- `all_connections(work_id)` -> list of `%{type, why, from: node, to: node}` for every edge of those six types whose both nodes exist, in edge order.

**Graph build trace**
- `record_event(attrs)` W graph_events: insert; ANY exception is caught, logged (`"marginalia: graph event not recorded: ..."`) and `{:error, :not_recorded}` returned. Never blocks the build.
- `list_events(work_id)`: `order by id asc`. `clear_events(work_id)`: delete all.
- `event_stats(work_id)` -> `%{calls, refused (ok == false), by_tool: %{tool => n}, refusals: %{kind => n}}`, where a refused event's kind is, in order: `result == nil` -> "unknown"; result contains "character for character" -> "quote not in draft"; contains "flow rule" -> "flow rule"; contains "not a step in" -> "flow rule"; contains "unknown node id" -> "unknown node id"; else "other".
- `reset_read(work_id)` W edges, nodes, graph_events, sections: transaction: delete edges touching any node of the work, delete all nodes, clear events, set every section `status = "pending"`. Does not touch work.status, first_impression, section summaries. Returns `{:ok, :ok}`.
- `reset_decision_graph(work_id)` -> `{:ok, n}`: ids of nodes of types `goal option decision action outcome observation revisit`; delete edges touching them, delete those nodes, clear events; n = number of nodes deleted. Beats, spine, threads, questions and edges between survivors remain.

**Revisions and baseline**
- `revisions(work_id)` `order by seq asc`; `revision_count(work_id)`.
- `baseline(work)`: stored `baseline_body` if a non-empty binary. Otherwise reconstruct: start from `work.body`, walk revisions NEWEST first, and for each whose `after` is contained in the running text, replace the first occurrence of `after` with `before`; one whose `after` is absent is skipped. (A draft with no revisions and no baseline returns its body.)
- `replay(work_id)` -> `{:ok, body}` | `{:error, seq}`: start from `baseline(work)`, apply each revision in seq order replacing the first occurrence of `before` with `after`; halt `{:error, seq}` at the first revision whose `before` is not present.
- `record_revision` (private): `seq = coalesce(max(seq), 0) + 1` for the work; insert `{work_id, section_id, section_ordinal, seq, before, after, origin: to_string(opts[:origin] || "edit"), note: opts[:note]}`.

**Corrections**
- `record_correction(attrs)`; `list_corrections(work_id)` `order by id desc`.

**Editing**
- `replace_block(section, old_block, new_text, opts \\ [])` (opts `origin:` "edit"/"rewrite"/"summary", `note:`):
  1. `old_block = to_string(old_block)`.
  2. `new_text = new_text |> to_string |> trim_trailing |> Sentences.reflow` (so a pasted one-liner is stored one-sentence-per-line before comparison).
  3. If `trim(new_text) == ""` -> `{:error, :empty}`.
  4. If `new_text == old_block` -> `{:ok, %{section: section, superseded: 0}}` (no revision written).
  5. If `old_block` is not a substring of `section.body` (byte-wise `contains?`) -> `{:error, :moved}`.
  6. Else in one transaction: `body = replace first occurrence of old_block in section.body with new_text`; update the section `body` and `word_count` (ASCII word count); `supersede_unanchored(section)`: for each node of that section with a non-empty quote and status != "superseded" whose quote no longer verifies (`Anchor.verify(quote, section.body) == :error`), `set_node_status(.., "superseded")`, counting successes; `record_revision(section, old_block, new_text, opts)` (a failure here raises a match error and rolls back); `rebuild_work_body(work_id)`: body = all sections' bodies joined "\n\n", word_count recomputed, `updated_at` = now. Returns `{:ok, %{section: updated_section, superseded: n, revision: rev}}`.
  The section keeps its boundaries; notes are marked, never deleted; summaries are NOT touched (they become stale through their fingerprint). Anything outside `Anchor`'s normalisation counts as "moved": a quote that still verifies after the edit survives.
  Examples (tests): editing `"The kettle went cold on the counter."` to `"The kettle went stone cold."` supersedes the kettle node (n = 1) and leaves the window node `pending`; replacing it with `"Nobody moved. The kettle went cold on the counter."` supersedes nothing; `replace_block(s, b, "   ")` -> `{:error, :empty}`; `replace_block(s, "a paragraph that is not there", "new")` -> `{:error, :moved}`; replacing a span crossing two paragraphs (old_block contains "\n\n") works and records ONE revision with both paragraphs in `before`; a re-wrap-only edit of a stored paragraph records nothing.
- `superseded_count(work_id)`: count of nodes with status "superseded".

### 4.2 `Marginalia.Reading`

- `page(work, opts \\ [])` R sections, nodes, edges. Returns a list, one entry per section (filtered by `opts[:section]` ordinal when given), each `%{section, blocks, unplaced}`:
  - notes = `opts[:notes]` if supplied, else `collect(nodes, all_connections, opts[:only])`.
  - `collect`: beat notes `%{id: {:beat, id}, key: "beat:#{id}", section_id, kind: "beat", quote, title, body, stale: status == "superseded"}` for every node with node_type "beat"; connection notes, one per entry of `all_connections` whose FROM node is a beat with non-nil section_id: `%{id: {:conn, from_id, to_id, type}, key: "conn:#{from_id}:#{to_id}:#{type}", section_id: from's, kind: type, quote: from beat's quote, title: label(type) <> " " <> to.title, body: why, stale: false}`. `label`: develops -> "develops →", pays_off -> "pays off →", requires -> "requires ←", tension -> "tension with", realises -> "realises", asks_about -> "asks about", else the type. `only`: "beats" -> beat notes; "connections" -> connection notes; "tensions" -> connection notes with kind "tension"; anything else -> beats then connections.
  - Per section: `paragraphs = split(section.body)`; fold over paragraphs with a `placed` set of note ids: `mine` = notes (for this section) not yet placed whose quote is non-empty and `Anchor.verify(quote, paragraph)` returns a non-empty span; add them to placed; `mark` = the first span found among `mine` in order (one highlight per paragraph); block = `%{text: paragraph, mark, notes: mine, ref: "s#{ordinal}p#{index}"}` (index = zero-based position in the split list, headings and code included). `unplaced` = the section's notes never placed.
- `split/1`, `render_block/4`, `plain/1`, `outline/1`, `heading?/1`, `heading_level/1`, `heading_text/1`: section 2.
- `focus(work, key)`: key `"beat:ID"` -> `%{kind: "beat", title, body, quote, sections: [its section]}`; `"conn:FROM:TO:TYPE"` -> both nodes must exist; `why` = rationale of the matching connection (from, to, type) or nil; `%{kind: TYPE, title: "#{a.title}  —#{type with _ -> space}→  #{b.title}" (two spaces around the arrow text), body: why, quote: a.quote, sections: [a's section, b's section] without nils, uniq by id}`. Anything unparsable or missing -> nil.
- `rows(blocks)`: group blocks into rail rows: scan blocks; an un-annotated block (`notes == []`) joins the pending run; an annotated block closes a row `%{blocks: run + [block], notes: block.notes}`; trailing un-annotated blocks become a last row `%{blocks: run, notes: []}`.
- `cite(work, text)`: `Selection.locate(work, text)`; ok -> `%{text: span, section: section.title, ordinal: section.ordinal}`; error or non-binary -> nil.
- `grounding(work, node_id)`: edges of types `realises` and `asks_about` touching `node_id` (either end), the node on the other end must be a beat; unique by node id; each -> `%{id, title, quote, why: rationale, section}`; sorted by `{section ordinal (nil first), id}`; returns `%{beats: [...], sections: unique non-nil sections in that order}`.

### 4.3 `Marginalia.Chat` (persisted conversations)

Constants: UI history limit 60, `context_limit` 20 (messages actually sent), `message_limit` 100 (lifetime user messages per account).
- `latest_conversation(work_id)`: newest (`id desc`) conversation with `anchor_kind == "work"`. `get_or_create_conversation(work_id)` returns `{:ok, convo}` creating one with the default mode "read" if none.
- `create_conversation(work_id, mode \\ nil)`: insert with `mode || "read"`; invalid mode -> `{:error, changeset}`.
- `set_mode(convo, mode)`: changeset update (`mode is invalid` for unknown); history is kept.
- `list_conversations(work_id)` / `list_open_conversations(work_id)`: work-anchored only, `id desc`, limit 30.
- `get_conversation(work_id, id)`.
- `conversation_summaries(work_id)`: for each listed conversation `%{id, mode, messages: count, title: c.title || summarise(first user message), at: inserted_at}`; `summarise`: nil -> "New thread"; else collapse whitespace, trim, if longer than 52 graphemes `slice(0, 51) <> "…"`.
- `history(conversation_id, limit \\ 60)`: last `limit` messages by `id desc`, reversed to chronological, as `[%{"role" => r, "content" => c}]`.
- `context_window(history)`: last 20 elements.
- `append(conversation_id, role, content)` role in user/assistant: insert; ANY exception swallowed; always `:ok`. Other roles -> `:ok` without writing.
- `delete_conversation(c)`.
- `search(work_id, query, limit \\ 8)`: terms as 2.10 (none -> `[]`); candidate messages = newest 400 messages (by id desc) across all conversations of the work; score = number of terms contained in `downcase(content)`; keep > 0; sort by score descending (stable, so newer first among equals); take `limit`; each `%{who: role, said: first 600 graphemes of content, at: inserted_at}`.
- `messages_sent(user_id)`: count of `role == "user"` messages in conversations of works owned by the user (all drafts). `remaining(user)`: `:unlimited` if `Accounts.owner?(user)` else `max(100 - messages_sent, 0)`. `allowed?(user)` = remaining != 0.
- `thread_for_block(work_id, section_id, block_ref, opts)` (opts `quote:`, `mode:`): look up the conversation with this `(work_id, block_ref)`; if none insert `%{work_id, section_id, block_ref, anchor_kind: quote ? "span" : "block", quote, mode: opts[:mode] || "read"}`; if one exists and `opts[:quote]` is non-nil and differs from the stored quote, update `quote` and set `anchor_kind: "span"`; else return it unchanged. Always `{:ok, convo}` (or `{:error, cs}`).
- `threads_by_block(work_id)`: map `block_ref => %{id, messages: count, quote, resolved: resolved_at != nil, mode}` for conversations with a non-nil block_ref.
- `resolve_thread(convo, resolved?)`: set `resolved_at` to now (seconds) or nil.

### 4.4 `Marginalia.Graph` (export)

- `export(work)` -> map: `work: %{id, title, intent, words: word_count, sections: count, status, first_impression, exported_at: ISO8601 UTC}`; `nodes` (ordered like `list_nodes`), `edges` (ordered like `list_edges`), `themes: []`, `node_themes: []`.
- Node JSON: `id`; `node_type` mapped spine->goal, beat->action, thread->observation, question->decision (others unchanged); `marginalia_type` = native type; `title`; `description`; `body`; `quote`; `narrative`; `section` (title or nil); `section_ordinal`; `status` (or "pending"); `created_at` = inserted_at; `metadata_json` = a JSON STRING of `{branch, section, narrative, ordinal, status, anchored: quote non-empty}` where `branch` = `"section-#{ordinal}"` if the node has a section, else `"spine"` for spine nodes, else `node_type <> "s"`.
- `description`: if quote non-empty: `[body, "Sources:", "- \"#{quote with \n -> space}\""]` minus nil/"" joined by "\n\n"; else body.
- Edge JSON: `id, from_node_id, to_node_id, edge_type, weight: 1.0, rationale, created_at`.
- `to_json(work)` = pretty-printed JSON of export. `to_dot(work)`: lines `digraph marginalia {`, `  rankdir=TB;`, `  node [shape=box, style=rounded];`, one `  n#{id} [label="#{escape(title)}", color="#{colour(marginalia_type)}"];` per node, one `  n#{from} -> n#{to} [style=#{solid if edge_type == "follows" else dashed}, label="#{edge_type}"];` per edge whose both ends are exported nodes, then `}`; joined "\n". Colours: goal #8a3324, option #b45309, decision #1e3a8a, action #166534, outcome #0891b2, observation #6b665e, revisit #7c2d92, spine #8a3324, beat #166534, thread #0891b2, question #7c2d92, other #9a948a.
- `stats(work)` -> `%{nodes: n, edges: n, anchored: count of metadata anchored == true, by_type: frequencies of marginalia_type}`.

### 4.5 `Marginalia.Rewrite` (public API; the prompt is in section 5)

- `propose(work, span, opts)` (opts `provider:`, `steer:`) -> `{:ok, %{reading, original, section, candidates, spans_blocks, covers}}` | `{:error, reason}`:
  1. `check_length`: word count of span > 2500 -> `{:error, {:span_too_long, n, 2500}}`.
  2. `Selection.locate(work, span)`; `:error` -> `{:error, :not_in_draft}`; else `section` and `found` (the source span, which replaces the user's text from here on).
  3. The model call (section 5.9). Error passes through (`:truncated`, `:no_tool_call`, `:invalid_json`, `:rate_limited`, `{:http, ...}`, `:no_api_key`). A reply without a `"rewrites"` key is a match failure: `{:ok, %{...}}` that does not match returns itself as the `with` else value, i.e. the raw reply map is returned unchanged (callers treat it as an unexpected shape; a port should return `{:error, :no_candidates}`).
  4. `clean(raw, found)`; empty -> `{:error, :no_candidates}`.
  5. `reading: out["reading"]`, `original: found`, `section`, `candidates`, `spans_blocks: paragraph_around(section.body, found) == nil`, `covers: covered_refs(section, found)`.
- `clean(raw, original)`: keep map items; build `%{text: trim_text(r["text"]), move: one_line(r["move"]), cost: one_line(r["cost"])}`; drop candidates whose text is nil/""; drop those equal to the original after `squash`; unique by `squash(text)`; take 4. `squash(t)`: downcase, replace `[^\p{L}\p{N}]+` (u flag) with " ", trim; nil -> "". `trim_text`: trim; remove a leading label `^(option|candidate|version)\s*\d*\s*[:.\-—]\s*` (case-insensitive); trim; if wrapped in straight `"..."` or curly `“...”` remove the outer pair (slice 1..-2); trim. `one_line`: collapse `\s+` to " ", trim, slice to 160 graphemes (nil stays nil).
- `covered_refs(section, span)`: `[]` if the span is not byte-wise in the body; else for each paragraph of `Reading.split(body)` (zero-based index i) located by byte-wise first occurrence in the body `(p_start, p_len)`: include `"s#{ordinal}p#{i}"` when `p_start < span_end and span_start < p_end` (touching is not overlapping).
- `paragraph_around(body, span)` (private): first paragraph of `Reading.split(body)` for which `Selection.in_block(para, span) != nil`, else nil.
- `place(block, original, seed)` all binaries: if `block` contains `original` -> `{:ok, block with the first occurrence replaced by seed}`; else `:not_here`. `place(_, _, seed)` with non-binary block/original -> `{:ok, seed}`.
- `answer_budget`, `span_label`, `span_extent`, `steer_block`, `max_steer_chars/0 = 400`, `diff/2`: section 2.
- `prompt/0`, `tool/0`, `passes/0`: return the prompt text, the tool definition and `[%{id: "rewrite", name: "On request — rewrite one selected span", model: LLM.default_model(), runs: "only when the writer selects a span and asks", produces: "three labelled candidates, each with the move it makes and what it costs", prompt: @prompt}]`.

### 4.6 `Marginalia.Summary` (one section summary)

- `fingerprint(section)` = lowercase hex SHA-256 of `section.body || ""`.
- `current?(section)`: summary nil -> false; else `summary_fingerprint == fingerprint(section)`. (A non-nil summary with nil fingerprint is not current.)
- `drift(section)`: current -> `[]`; `summary_body` nil -> `[]`; else `Diff.rows(summary_body, section.body)`.
- `spine/2`, `previous_block/2`: section 2.10.
- `run(section, opts)` (opts `provider:`) R works, sections; W sections: `body = first 12_000 graphemes of section.body`; blank (trimmed) -> `{:error, :empty}`; `siblings = list_sections(work_id)`; one LLM call (section 5.5); on `{:ok, raw}` -> `validate` then `store`; on error log warning and return `{:error, reason}`.
- `validate(raw, body, ordinal)` -> `{attrs, dropped}`: `summary` = trimmed raw["summary"] (non-binary -> ""); `covers`: items trimmed (non-binary -> "" -> dropped), empties removed, unique, each kept iff `downcase(term)` is a substring of `downcase(body)` (the CAPPED body), else adds the dropped reason `covers: #{inspect(term)} is not in the section` (inspect = double-quoted Elixir string); `follows_from`: each item via `as_int` (integer; or a string parsed with leading-integer parse after trim; else nil): integer with `1 <= i < ordinal` kept; other integers add `follows_from #{i}: not an earlier section`; non-numbers add `follows_from #{inspect(n)}: not a number`; `sets_up` trimmed, "" -> nil. attrs: `%{summary, summary_covers: first 6 of kept, summary_follows: unique, summary_sets_up}`.
- `store`: `summary == ""` -> `{:error, :no_summary}`; else update the section: the attrs plus `summary_fingerprint = fingerprint(section)`, `summary_body = section.body` (FULL body), `summarised_at` = now (seconds), `summary_dropped = dropped`. Returns `{:ok, section}`.
- `section(work_id, ordinal)` = `Works.get_section`.
Examples: `validate(%{"summary"=>"s","covers"=>["out-grammar","monad transformers"]}, "The out-grammar declares the syntax, and kcodegen expands it into Blimp.kt.", 3)` -> covers `["out-grammar"]`, dropped has one reason mentioning `monad transformers` and `not in the section`; `follows_from [1,2,5,3]` at ordinal 3 -> `[1,2]` and 2 dropped reasons; `covers` = `["kcodegen","kcodegen"] + 10x"out-grammar"` -> `["kcodegen","out-grammar"]`; `"Out-Grammar"` kept (case-insensitive) with the model's casing; `sets_up "  "` -> nil.

### 4.7 `Marginalia.Document` (whole-draft summary)

- `run(work, opts)` (opts `provider:`, `force:`) -> `{:ok, %DocumentSummary{}}` | `{:error, reason}`:
  1. sections empty -> `{:error, :no_sections}`.
  2. `fan_out_sections`: `todo` = all sections if `force` else those where `Summary.current?` is false. Run `Summary.run(section, opts)` for each with `Task.async_stream`, max concurrency 6, timeout 180_000 ms, `on_timeout: :kill_task`; results ignored. Re-list sections.
  3. `summarised` = sections with non-nil summary; none -> `{:error, :no_summaries}`.
  4. Two concurrent LLM tasks (5.6, 5.7): compose over `summarised`, guidelines over all `sections` + `summarised`. `Task.await_many(tasks, 180_000)`.
  5. both ok -> `store`; compose ok + guidelines error -> `store_partial` (stores with `guide = %{}` and appends to `dropped` the entry `"the guidelines pass failed: #{inspect(reason)}"`); compose error -> `{:error, reason}`.
  6. `upsert`: `get(work.id)` or a new row; changeset with `validate(...)` attrs plus `work_id`, `fingerprint = fingerprint(sections)` (the sections list as fetched after the fan-out), `dropped`; `Repo.insert_or_update`.
- `validate(comp, guide, sections)` -> `{attrs, dropped}`: `ordinals` = set of section ordinals. For `comp["movements"]`, `guide["guidelines"]`, `guide["tensions"]` (nil -> []): keep map items only; for each, `cited = item["sections"] || []`, `good` = cited entries that are integers present in `ordinals`; `missing` = the rest; if any missing add `"#{label}: cites #{inspect(missing)}, which are not sections here"` (label "movement"/"guideline"/"tension"; inspect = Elixir list syntax e.g. `[14]`); the item is kept with `"sections"` replaced by `good` (even when empty). attrs: `%{summary: trimmed (non-binary -> ""), throughline: trimmed, movements, guidelines, tensions}`. Order of `dropped`: movements, then guidelines, then tensions.
- `fingerprint(sections)`: for each section `"#{ordinal}:#{Summary.fingerprint(s)}:#{:erlang.phash2(s.summary)}"`, joined with "|", SHA-256, lowercase hex. `phash2` is Erlang's portable term hash (an integer in 0..2^27-1) of the summary string (nil hashes too). A port must pick its own stable string hash; existing stored fingerprints will not match and every document summary will read as stale once, which is harmless.
- `current?(work)`: stored row exists and `doc.fingerprint == fingerprint(list_sections(work.id))`.
- `get(work_id)`: the row or nil.
- `to_draft(user_id, work)` -> `{:ok, new_work}` | `{:error, :nothing_summarised}` (also any `create_work` error): `summarised` = sections with a summary not nil/""; none -> error. Creates a new work through `Works.create_work(user_id, %{"derived_from_id" => work.id, "title" => "#{work.title} — in summary", "intent" => "A condensation of #{work.title}: #{n} of its #{total} sections, in order. It is meant to read as an argument in its own right, so the test of any part is whether it stands without the section it came from.", "body" => draft_body(...)})`. Not placed in any folder (`folder_id` nil).
  `draft_body`: `opening` = if the document summary exists with a non-empty `summary`: `[summary, throughline]` minus nil/"" joined "\n\n"; else `"A condensation of #{work.title}, section by section."`. One part per summarised section: lines `["## #{ordinal}. #{title}", "", summary, covers_line, sets_up_line]` minus nils, joined "\n", where `covers_line` = `"\nIt deals with: " <> Enum.join(summary_covers, ", ") <> "."` when covers is a non-empty list, and `sets_up_line` = `"\nIt leaves in place: " <> summary_sets_up` when non-empty. Final rules part when `guidelines` is a non-empty list: `"## What it is working under\n\n" <> join("\n\n", "#{rule["guideline"]} #{rule["because"]}")`. Result: `([opening] ++ parts ++ [rules_part])` minus nils, joined "\n\n", trimmed. Note: the segmenter then splits this on the `##` headings, so the `##` lines disappear from the body and become section titles.
- `compare(user_id, work, opts)` (opts `provider:`, `on_stage: fn(stage_string)`) -> `{:ok, %{draft: summary_work, link: link}}` | `{:error, reason}`:
  1. `condensation(user_id, work)`: `Works.condensation_of(work.id)` or `to_draft` (error `:nothing_summarised` propagates).
  2. `read(summary, opts)`: if the condensation has no nodes: call `on_stage.("reading the summary")`, run `Analysis.run(summary, provider)` synchronously and reload the work; else reuse.
  3. `Links.get_or_create(work.id, summary.id)` (pair stored lowest id first; creates the row `status "pending"`).
  4. `on_stage.("relating")`, then `Linker.run(link, provider)` synchronously (its return value is ignored; failure is visible only in `link.status`). Returns `{:ok, %{draft: summary, link: link}}` with the link as it was BEFORE the linker updated it.
  `on_stage` callbacks are plain functions the caller provides (the web layer maps them to `Runs.progress(key, stage: stage)`).

### 4.8 `Marginalia.Analysis` (the Read) — public functions

- `topic(work_id) = "work:#{work_id}"`.
- `start(work, provider \\ nil)`: `Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn -> run(work, provider) end)`; returns `:ok` immediately (fire and forget; no handle is kept, nothing can cancel it).
- `run(work, provider \\ nil)` -> `{:ok, work}` always (see section 6 for the pipeline).
- `beat_target(words) = min(max(div(words, 220), 2), 14)`. `beat_ceiling(words) = t + max(div(t, 2), 1)` with `t = beat_target(words)`. Values: target(100)=2, target(1100)=5, target(100000)=14; ceiling(t=2)=3, 3->4, 4->6, 5->7, 14->21; always `t < ceiling < 2t`.
- `thin(beats, ceiling, section_id)`: if `n <= ceiling` unchanged; else log info `"marginalia: section #{section_id} returned #{n} beats, thinning to #{ceiling}"`; `step = (n - 1) / (ceiling - 1)` (float division); pick `Enum.at(beats, round(i * step))` for `i` in `0..ceiling-1` (`round` = half away from zero), then `uniq`. Keeps first and last, evenly spaced. Test: 3x ceiling beats thin to exactly `ceiling`, first = "beat 1", last = "beat #{3*ceiling}".
- `beats_tool/0` returns the tool schema (5.1). `passes/0` returns `[beats, spine] ++ Weave.passes()` with `%{id, name, model, runs, produces, prompt}`: `id "beats"`, name `"Pass 1 — read each section"`, model `LLM.fast_model()`, runs `"once per section, 3 at a time"`, produces `"beats, each anchored to a verbatim quote"`; `id "spine"`, name `"Pass 2 — the whole draft"`, model default, runs `"once, after every section is read"`, produces `"first impression, spine, threads, open questions"`.

### 4.9 `Analysis.Weave`, `Analysis.Linker`, `Analysis.DecisionGraph`

Documented with their calls in section 5 (5.3, 5.4, 5.8). Public surface:
- `Weave.types/0`, `Weave.prompt/0`, `Weave.passes/0`, `Weave.run(work, provider \\ nil)` -> `{:ok, n_edges}` | `{:error, :no_edges}` | `{:error, llm_reason}`.
- `Linker.types/0` (`develops pays_off requires tension answers echoes`), `Linker.prompt/0`, `Linker.passes/0`, `Linker.start(link, provider)` (detached, returns `:ok`), `Linker.run(link, provider)`.
- `DecisionGraph.flow/0`, `tools/0`, `passes/0`, `topic/1`, `start(work, opts)`, `run(work, opts)`, `execute(call, state)` (public so tests drive it).

### 4.10 `Marginalia.Chat.Editor`

- `tools/0` (5.10), `system_prompt/0`, `modes/0` (list of `%{id, label, blurb, opener, stance}`), `mode_names/0 = ["read","provoke","bounce"]`, `default_mode/0 = "read"`, `mode(id)` (unknown/nil -> the first mode, "read"), `opener(mode_id \\ nil)`.
- `ask(work, history, opts)` (opts `provider:`, `mode:`, `focus:`, `cited:`) -> `{:ok, text}` | `{:error, string}`: section 5.10.
- `run_call(work, %{"id" => id, "function" => %{"name" => n, "arguments" => json}})` -> `%{"role" => "tool", "tool_call_id" => id, "content" => Jason.encode!(result)}`; arguments that do not decode to a map become `%{}`.

### 4.11 `Marginalia.Diffs` (unified patch reader)

- `parse(patch)` -> list of `%Hunk{path, heading, lines}`: split on "\n"; a line matching `^diff --git a\/(?<a>.+?) b\/(?<b>.+)$` flushes the current hunk and sets `path` = group `b`; a line matching `^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(?<heading>.*)$` flushes and starts a hunk `{path (current), heading: trim(heading), lines: []}`; inside a hunk, any line whose first character is " ", "+" or "-" is appended (so `--- a/x` and `+++ b/x` header lines that appear after `diff --git` but before the first `@@` are ignored because there is no current hunk; within a hunk they are never present before the next `diff --git`); other lines ignored. Non-binary -> `[]`.
- `files(patch)`: unique paths in order of first appearance.
- `added(hunk)`: lines starting "+" with the first character removed, joined "\n".
- `sample(hunk)`: lines starting "+" or " " with the first char removed, joined "\n", then `String.trim(.., "\n")` (strip leading/trailing newlines).
- `find(patch, quote)`: first hunk for which `Cuts.locate(quote, added(hunk))` is non-nil. `Cuts.locate(needle, haystack)` (outside scope): nil if needle is blank; the needle itself if `haystack` contains it exactly; else collapse whitespace in the needle (`\s+` -> " ", trim) and search a whitespace-collapsed copy of the haystack (ASCII whitespace runs -> one space, leading whitespace dropped) byte-wise, returning the haystack's own bytes for the matched range; else nil.

### 4.12 `Marginalia.Tour`, `Walkthrough`, `Walkthrough.Cases`: static data

Pure lookup tables. `Tour.for_view(atom)` -> `%{title, points: [string]}` or nil; `Tour.views/0` -> `["follow","graph","prompts","read","spine","threads","trace"]` (atom keys sorted). `Walkthrough.steps(:read, mine?: bool)` -> the 10 `@read` steps; `mine?: false` drops steps with `owner: true` (ask, rewrite, edit); other views -> `[]`; `for_view?(view)` = steps(view, mine?: false) != []; `views/0 = ["read"]`; `rewrite/0` and `exchange/0` fixtures; `Cases.steps(:cases | :follow | :case_read)` else `[]`; `Cases.for_view?`. Step shape: `%{id, title, body, target (css selector or nil), place ("left"|"right"|"bottom"|"top"|"centre"), owner: true (optional), act: (optional) %{kind: "push", event, params} | %{kind: "client", name} | %{kind: "hop", to} | %{kind: "click", target}}`. The data, verbatim:

Tour (`@tours`):
```
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

Walkthrough read steps (`@read`), and the fixtures:
```
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
```
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
```
```
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
```

Cases steps:
```
@index [
  %{
    id: "hook",
    title: "One real disagreement, first",
    body:
      "Every case leads with the sharpest thing found between its documents, in the terms the pass used. Not a summary of the case — a place where two of its documents pull against each other.",
    target: ".cs-case:first-of-type .cs-hook",
    place: "bottom"
  },
  %{
    id: "held",
    title: "The holding is the Court's own sentence",
    body:
      "Quoted out of the opinion, not paraphrased, and not taken from the Reporter's syllabus — which is no part of the opinion and says so on its own first page. Three of these sixteen never state their holding in one sentence, and those show none at all.",
    target: ".cs-case:first-of-type .cs-held",
    place: "bottom"
  },
  %{
    id: "ways",
    title: "A case is read one document against another",
    body:
      "Not 'open the case'. The opinion against the dissent, the opinion against the advocate it is answering — each with how much the two actually have to say to each other, which is the honest signal of which to open.",
    target: ".cs-case:first-of-type .cs-ways",
    place: "top"
  },
  %{
    id: "kin",
    title: "And the term argues with itself",
    body:
      "Cases are related across the term too, chosen by the vocabulary the opinions actually share rather than by anyone's idea of a theme. It is the only thing here that could not have come from reading one case carefully.",
    target: ".cs-case:first-of-type .cs-kin",
    place: "top"
  },
  %{
    id: "sources",
    title: "Everything links back to the PDF",
    body:
      "The whole claim of this site is that none of it is invented. The only way to make that checkable is to keep the Court's own file one click away, so every document does.",
    target: ".cs-case:first-of-type .cs-parts",
    place: "top"
  },
  %{
    id: "into",
    title: "Now the reading itself",
    body:
      "This is where the site actually happens. Opening the strongest pairing in the first case.",
    target: ".cs-case:first-of-type .cs-ways li:first-child",
    place: "top",
    act: %{kind: "hop", to: "first_pair"}
  }
]
```
```
@follow [
  %{
    id: "sides",
    title: "Left is read. Right is the reference",
    body:
      "One document down the left at your own pace. The other is dimmed on purpose — it lights up only where it has something to say about the passage you are on.",
    target: ".fl-colhead",
    place: "bottom"
  },
  %{
    id: "follow",
    title: "The right side follows you",
    body:
      "Scroll the left and the right is scrolled for you, snapping to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.",
    target: "#fl-lead",
    place: "right"
  },
  %{
    id: "wire",
    title: "The line runs through the reason",
    body:
      "Left passage, why, right passage — the actual shape of the claim. The middle is the reason for drawing it, and it belongs to neither document.",
    target: ".fl-mid",
    place: "left"
  },
  %{
    id: "filter",
    title: "One kind of relation at a time",
    body:
      "Tension leaves only where the two genuinely pull apart. Answers leaves where one replies to the other. The filter changes what the page is about, not how much of it there is.",
    target: ".fl-legend",
    place: "bottom",
    act: %{kind: "push", event: "set_only", params: %{"only" => "tension"}}
  },
  %{
    id: "filter_back",
    title: "Everything, again",
    body: "Back to the whole relationship, which is how it opens.",
    target: ".fl-legend",
    place: "bottom",
    act: %{kind: "push", event: "set_only", params: %{"only" => "all"}}
  },
  %{
    id: "gaps",
    title: "The quiet stretches are folded",
    body:
      "Where the two have nothing to say to each other, the prose is folded away with its size on the label. Nothing is deleted — open one and read it.",
    target: ".fl-gap",
    place: "right"
  },
  %{
    id: "chat",
    title: "You can argue with it",
    body:
      "Click the line between two passages and both go into the question. The chat starts fresh on this page and holds whatever you cite into it.",
    target: ".lc",
    place: "left"
  },
  %{
    id: "onward",
    title: "Two documents is the pair. Now the whole case",
    body: "The same opinion, with every other document in the case beside it at once.",
    target: ".fl-colhead",
    place: "bottom",
    act: %{kind: "hop", to: "case_read"}
  }
]
```
```
@case_read [
  %{
    id: "margin",
    title: "The whole case in one margin",
    body:
      "The dissent and every advocate, against the same paragraph, each saying which one it is. Reading the pairs separately is exactly what this hides — and the paragraphs where all of them speak at once are the ones worth having.",
    target: ".cr-grid .cr-notes:not(.bare)",
    place: "left"
  },
  %{
    id: "row",
    title: "A paragraph and its notes are one row",
    body:
      "One hairline runs from the left edge of the paragraph, across the gutter, into its notes. They are level because the layout says so — there is no scrolling machinery here to drift.",
    target: ".cr-text.linked",
    place: "right"
  },
  %{
    id: "who",
    title: "Filter by who is speaking",
    body:
      "Each chip is one of the other documents, with how often it has something to say. A dashed chip is another case in the term rather than another document in this one.",
    target: ".cr-srcs",
    place: "bottom"
  },
  %{
    id: "lead",
    title: "Read it from anyone's side",
    body:
      "Any document in the case can be the one you read. The dissent with the majority in its margin is a different experience from the reverse, and both of them are the case.",
    target: ".cr-pick",
    place: "bottom",
    act: %{kind: "click", target: ".cr-pick > summary"}
  },
  %{
    id: "done",
    title: "That is the whole of it",
    body:
      "Sixteen cases, eighty-two documents, each read on its own and then related. Every connection is anchored to a sentence in both documents, and anything that could not be found in both was discarded before it was stored.",
    target: nil,
    place: "centre"
  }
]
```

Constraints enforced by `walkthrough_test.exs`: step ids unique and non-empty; every `place` in the five allowed; `act.kind` "push" needs a binary `event`, "client" needs a `name` in `open_map open_thread ask_thread select rewrite edit reset`; the last read step has `act == %{kind: "client", name: "reset"}`; steps JSON-encode; `rewrite().candidates` entries have exactly the keys `text, move, cost` (same as `Rewrite.clean/2` output).

---

## 5. Every LLM call

### 5.0 The client contract (`Marginalia.LLM`, outside this scope but every call goes through it)

Three entry points, all taking a keyword list:

- `LLM.chat(opts)` -> `{:ok, message_map}` | `{:error, reason}`. `message_map` is the provider's `choices[0].message` (string keys: `"role"`, `"content"` (may be nil), `"tool_calls"` (list of `%{"id","type","function" => %{"name","arguments" => json string}}`, only when present)).
- `LLM.json(opts)`: `chat` with `json: true`; decodes `message["content"]` as JSON; a JSON object -> `{:ok, map}`; anything else (not an object, empty, nil, invalid) -> `{:error, :invalid_json}`.
- `LLM.call_tool(opts)` with `tool:` (one tool schema): sends `tools: [tool]`; `tool_choice` is forced to `{"type":"function","function":{"name": tool name}}` ONLY when `effort` is `:none`/"none", otherwise `"auto"` (DeepSeek refuses forced choice while reasoning). Result: the first `tool_calls[0].function.arguments` decoded as a JSON object -> `{:ok, map}`; undecodable -> `{:error, :invalid_json}`; reply without tool calls -> `{:error, :no_tool_call}`.

Options: `:provider` ("openai" | "deepseek" | atoms | nil; unknown -> deploy default), `:model`, `:messages` (required; list of `%{"role" => "system"|"user"|"assistant"|"tool", "content" => string, ...}`), `:tools`, `:tool_choice`, `:temperature`, `:effort` (`:none`, `:low`, `:high`; others ignored), `:json`, `:max_tokens`, `:timeout` (default 300_000 ms).

Request: HTTP POST (JSON body, header `authorization: Bearer <key>`, Req `receive_timeout` = timeout) to the provider's chat-completions endpoint. Body = provider `default_body` (`{"reasoning_effort": "low"}`) merged with `model` and `messages`; `reasoning_effort` overridden by `:effort`; `tools`; `tool_choice` (`opts[:tool_choice]` or `"auto"` when tools are present); `temperature`; the max-tokens field with value `asked + reasoning_headroom` (headroom 24_000 for both providers; the field is `max_tokens` for deepseek and `max_completion_tokens` for openai); `response_format: {"type":"json_object"}` when `json`. Nil options are omitted.

Providers: deepseek (default; endpoint `https://api.deepseek.com/chat/completions`; model and fast model both `deepseek-flash`; key from config `:deepseek_api_key`), openai (`https://api.openai.com/v1/chat/completions`; model `gpt-5.6-sol`; fast model `gpt-5.4-nano`; key `:openai_api_key`). Config overrides: `:llm_provider` ("openai" else deepseek), `:llm_model`, `:llm_fast_model`, `:llm_endpoints` (map key->url, for tests). `LLM.default_model(provider)` = config model or provider model; `LLM.fast_model(provider)` = config fast model or provider fast model. No key configured -> `{:error, :no_api_key}`.

Outcome handling: HTTP 200 with `choices[0]`: `finish_reason == "length"` -> `{:error, :truncated}` (NEVER retried; the caller must ask for less); otherwise `{:ok, message}`. HTTP 429/500/502/503/504 or a transport error: retried, 3 attempts in total, sleeping `2^attempt * backoff_ms (config :llm_backoff_ms, default 250)` plus 1..400 ms jitter between attempts (0 backoff in tests); after the last attempt `{:error, :rate_limited}` or `{:error, {:transport, inspect(reason)}}`. Any other status -> `{:error, {:http, status, first 300 chars of inspect(body)}}`. Usage tokens are logged at info and emitted as telemetry `[:marginalia, :llm, :usage]`.

Interpolation convention in the prompts quoted below: they are Elixir heredocs, reproduced here with the closing-delimiter indentation removed and `\`-newline continuations joined, exactly as the model receives them, EXCEPT `#{...}` interpolations which are left as written. Substitution is textual and the newline that ends the heredoc line stays. Recurring expressions:
- `INTENT` = `#{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}` (the label text varies per prompt: "What it is meant to do to a reader: " or "Intended effect on a reader: "): when intent is non-empty the line becomes `<label><intent>` followed by an extra "\n" (so a blank line follows); when empty the whole interpolation is the empty string, leaving an empty line.
- `String.slice(x, 0, n)` = first n graphemes.
Where a template contains a bare `#{name}` the value is described right after the template.

Summary of calls (details follow):

| # | Function | Model | effort | temp | max_tokens asked (+24000 sent) | JSON mode | mechanism |
|---|---|---|---|---|---|---|---|
| 1 | `Analysis.read_section` (beats) | fast | none | 0.3 | 4000 | no | `call_tool` record_beats (forced) |
| 2 | `Analysis.synthesize` (spine) | default | high | 0.5 | 6000 | yes | `LLM.json` |
| 3 | `Weave.run` | default | high | 0.4 | 8000 | yes | `LLM.json` |
| 4 | `Linker.ask` (+ crowded retry) | default | high | 0.4 | 24000 | yes | `LLM.json` |
| 5 | `Summary.ask` | fast | low | 0.2 | 1200 | no | `call_tool` report_section |
| 6 | `Document.compose` | default | high | 0.3 | 3000 | no | `call_tool` report_composition |
| 7 | `Document.guidelines` | default | high | 0.3 | 2500 | no | `call_tool` report_guidelines |
| 8 | `DecisionGraph.find_narratives` | default | high | 0.4 | 4000 | yes | `LLM.json` |
| 9 | `DecisionGraph.loop` (per narrative, up to 24 turns) | default | high | 0.4 | 4000 | no | `LLM.chat` with 3 tools |
| 10 | `Rewrite.ask` | default | high | 0.7 | `max(3000, words*7)` | no | `call_tool` propose_rewrites |
| 11 | `Chat.Editor.loop` (up to 8 turns) | default | (unset -> provider default "low") | 0.7 | 2000 | no | `LLM.chat` with 11 tools |

There are 11 call sites and 12 system prompts (beats, spine, weave, linker, summary, compose, guidelines, narratives, graph, rewrite, editor) plus the linker's crowded-retry addendum and the 3 chat stances (15 prompt texts in all); the longest is the editor system prompt (about 10,200 characters). All of these are used with `model: LLM.default_model(provider)` unless noted; `provider` is `opts[:provider]` (admin-chosen) or nil.

### 5.1 Beats, per section (`Analysis.read_section`)

Tool call, forced (`effort: :none`). Called once per section (3 concurrently). System prompt `@beats_prompt`:

```
You are reading one section of a manuscript for a structural map. You are not editing it
and not rewriting it.

A BEAT is one move the section makes: a decision, a reveal, a turn in the argument, a
change in who wants what, an image the section rests on. One move, not one sentence. If
two of your beats could be joined by "and then they also say", they are one beat and you
have split a single move in half.

HOW MANY. You are given a target and a hard limit. The target is roughly how many moves a
section this long makes; the limit is refused above. Returning twice the target means you
are listing sentences rather than naming moves. Going under is fine when the section
genuinely does little. Before you answer, count what you have, and if you are over the
limit, merge the ones that belong to the same move until you are not.

EACH BEAT
- title: one line under 90 characters, naming the move in plain words. Write it as
  something the writer DOES: "They set June 2020 as the baseline", not "The baseline".

PRONOUNS. Never assume anyone's gender; the rule is the same for everyone and it is
about evidence, not about a default.
- The writer is "they". A draft almost never states its author's gender, and neither the
  prose, the subject matter nor the name on the file is evidence of it.
- A person or character IN the draft gets whatever the draft itself uses for them. If it
  calls her she, write she. Use "they" only where the text has not said, and do not work
  it out from a name, a role or what they do.
- note: one or two sentences on what this does TO A READER, and what it sets up or pays
  off if it does either. A later pass uses these to work out what leads to what, so
  "introduces the thermostat metaphor the regulation chapters depend on" is worth ten
  times "discusses self-regulation". No praise, no grading, no advice.
- quote: a VERBATIM span copied exactly from the section, 8 to 40 words, that shows this
  beat on the page. Character for character. Do not paraphrase, do not tidy the
  punctuation, do not join two separate sentences with an ellipsis. A quote that is not
  in the text causes the whole beat to be discarded, and the server checks every one.
```

Tool definition (`@beats_tool`, also `Analysis.beats_tool/0`), as an Elixir map (string keys):

```
@beats_tool %{
  "type" => "function",
  "function" => %{
    "name" => "record_beats",
    "description" => "Record the beats of this section, in the order they happen on the page.",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "beats" => %{
          "type" => "array",
          "description" => "In document order. Merge beats that belong to the same move.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "title" => %{
                "type" => "string",
                "description" => "The move, as something the writer does. Under 90 characters."
              },
              "note" => %{
                "type" => "string",
                "description" => "What it does to a reader, and what it sets up or pays off."
              },
              "quote" => %{
                "type" => "string",
                "description" =>
                  "8 to 40 words, verbatim from the section. Verified server-side."
              }
            },
            "required" => ["title", "note", "quote"]
          }
        }
      },
      "required" => ["beats"]
    }
  }
}
```

User message (`beat_target`/`beat_ceiling` from section 4.8; the body is cut to the first 24,000 graphemes):

```
Manuscript: #{work.title}
#{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
Section #{section.ordinal}: #{section.title}
#{section.word_count} words. Aim for about #{beat_target(section.word_count)} beats.
HARD LIMIT: return at most #{beat_ceiling(section.word_count)}. More than that is refused.

---
#{String.slice(section.body, 0, 24_000)}
```

Template notes: `#{work.title}`, `#{section.ordinal}`, `#{section.title}`, `#{section.word_count}`; `#{if work.intent ...}` is INTENT with label `What it is meant to do to a reader: `. The INTENT interpolation occupies its own template line: with an intent the output has the intent line followed by one blank line; without, a single empty line.

Reply shape: `{"beats": [{"title": str, "note": str, "quote": str}, ...]}`. Handling:
- `{:ok, %{"beats" => list}}` -> `store_beats`; `{:ok, other}` -> section failed `"no beats returned"`; `{:error, r}` -> section failed `inspect(r)`.
- `store_beats`: non-map items dropped; each -> candidate `%{node_type: "beat", title: to_line(title), body: note (raw), quote: quote (raw)}`; drop candidates whose title is nil or "". `to_line(s)`: collapse `\s+` to " ", trim, first 300 graphemes; nil/non-string -> nil. `Anchor.filter(candidates, section.body)` keeps only verified quotes, replacing each quote by the source wording; discarded count is logged (`"marginalia: dropped N/M unanchored beats in section ID"`). `thin(kept, beat_ceiling(section.word_count), section.id)`. `Works.insert_nodes(work.id, section.id, kept)` (ordinal = position in the kept list). `follows` edges between consecutive inserted beats: `Works.link(work_id, a.id, b.id, "follows", i)` with i = 0,1,2... Section status -> "read"; broadcasts `{:section, section.id, "read"}` and `{:nodes, section.id, count}`.
- Failure: section status "failed", broadcast `{:section, id, "failed"}`, warning log `"marginalia: section #{id} failed: #{reason}"`.
- Retries: only the transport-level ones in the client. A `:truncated` or `:no_tool_call` fails the section; there is no re-ask.

### 5.2 Spine, first impression, threads, questions (`Analysis.synthesize`)

`LLM.json`, one call per read. Runs only if the work has at least one beat (else `{:error, :no_beats}`). System prompt `@spine_prompt`:

```
You are given the beat-by-beat map of a whole manuscript, in order. You have not been given
the full text, and you must not pretend you have.

Return JSON:
{
  "first_impression": "...",
  "spine": [{"title": "...", "note": "..."}],
  "threads": [{"title": "...", "note": "...", "status": "carried|dropped|thin"}],
  "questions": ["...", "..."]
}

- "first_impression": 3 to 5 sentences on what this draft is actually doing, as a reader
  experiences it. Be specific to THIS manuscript — name its people, its moves, its subject.
  No grading, no encouragement, no "this shows promise". If something is not working, say
  what, plainly.
- "spine": 6 to 12 nodes, the chain the whole work hangs off, in order. This is the load
  bearing structure, not a summary of every beat.
- "threads": 3 to 8 threads that run across sections. Mark "dropped" only when a thread
  stops well before the end with nothing closing it; "thin" when it appears once or twice
  and never develops.
- "questions": 4 to 6 questions for the writer. Each must name something specific from this
  draft. A question that could be asked of any manuscript is worthless — do not include one.
```

User message:

```
Manuscript: #{work.title}
#{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
#{length(sections)} sections, #{work.word_count} words.

#{outline}
```

where `#{outline}` is, for each section in ordinal order, `"## #{ordinal}. #{title} (#{word_count} words)\n#{lines}"` with `lines` = the section's beats (nodes of type beat, in `list_nodes` order) each as `"  - #{beat.title}"` joined "\n", and sections joined by "\n\n"; `#{length(sections)}` and `#{work.word_count}` as written; the first line is INTENT with label `What it is meant to do to a reader: `.

Reply shape: `{"first_impression": str, "spine": [{"title","note"}], "threads": [{"title","note","status": "carried"|"dropped"|"thin"}], "questions": [str]}`. Storage (`store_synthesis`; missing keys are treated as empty and the call still counts as success): spine -> nodes `{node_type "spine", title to_line(title), body note}`; threads -> `{node_type "thread", title, body "#{status} — #{note}"}` where status defaults to "carried" (and the em dash is U+2014 with spaces; a missing note interpolates as empty); questions (binary items only) -> `{node_type "question", title to_line(q)}`; items with empty titles dropped. Each group is inserted with `section_id` nil via `insert_nodes` (ordinals 0.. per group). Spine nodes are chained with `leads_to` edges, ordinal i. Then `update_work(work, %{first_impression: data["first_impression"], title: work.title, body: work.body})` (note: this reruns the Work changeset, recomputing `word_count` from `work.body`). Broadcasts `{:synthesis, :done}` and `{:stage, :spine, :done}`. On `{:error, reason}` from the call (including `:truncated`, `:invalid_json`) the run degrades (section 6).

### 5.3 Weave (`Analysis.Weave.run`)

`LLM.json`, after the spine. Skipped (`{:ok, 0}`) when the work has fewer than 2 beats. System prompt `@weave_prompt`:

```
You are given the complete map of a manuscript: every beat in document order, plus the
spine and the threads drawn over them. You are NOT given the full text and must not
pretend you have it.

Your job is the part the earlier passes could not do: say what leads to what.

So far the only connections in this map are "these two beats are next to each other on the
page" and "the spine runs in this order". That is not a model of an argument. Find the real
ones — especially the ones that cross sections, because those are the ones a writer cannot
see while working inside a single chapter.

Return JSON:
{"edges": [{"from": <id>, "to": <id>, "type": "...", "why": "..."}]}

TYPES
  develops  the later beat builds directly on the earlier one — same idea, carried further
  pays_off  the later beat delivers on a promise, setup or question the earlier one made
  requires  the later beat only works if the reader already has the earlier one
  tension   the two pull against each other, and the draft may not have noticed
  realises  this beat is where a spine node or a thread actually happens on the page
  asks_about  this open question is about this beat — every question should have one

RULES
- Use the numeric ids exactly as given. An id that is not in the list gets the edge thrown away.
- Prefer connections that CROSS sections. Two adjacent beats in the same section are already
  joined by document order; saying so again adds nothing.
- Every spine node should be linked by `realises` to the one or two beats where it actually
  happens. Every thread should be linked by `realises` to the beats it runs through.
- Every open question should be linked by `asks_about` to the beat or beats it is asking
  about. A question floating loose is a question the writer cannot act on.
- "why": one sentence, concrete to this draft, naming what passes between the two. Not
  "these are related". This sentence is shown to the writer beside the edge.
- A `tension` edge is a real claim: only draw one where the draft genuinely asserts two
  things that sit badly together. Do not manufacture them for interest.
- Quality over count. Thirty edges that are true beat a hundred that are plausible.
```

User message (`inventory`):

```
Manuscript: #{work.title}
#{if work.intent && work.intent != "", do: "Intended effect on a reader: #{work.intent}\n", else: ""}
#{beats}#{loose.("spine", "Spine")}#{loose.("thread", "Threads")}#{loose.("question", "Open questions")}
```

where `#{beats}` = for each section in ordinal order `"## Section #{ordinal}: #{title}\n#{lines}"` with lines `"  [#{id}] #{title}#{note}"` for that section's beats (node-list order), joined "\n", sections joined "\n\n"; and `#{loose.(type, label)}` appends, for the node types `spine` ("Spine"), `thread` ("Threads"), `question` ("Open questions") in that order, `"\n\n## #{label}\n"` followed by `"  [#{id}] #{title}#{note}"` lines joined "\n" (nothing when none of that type). `note(node)` = `" — #{first 160 graphemes of body}"` when body is a non-empty string, else "". INTENT here has label `Intended effect on a reader: `.

Reply: `{"edges": [{"from": id, "to": id, "type": str, "why": str}]}`. `{:ok, %{"edges" => list}}` -> store; `{:ok, other}` -> `{:error, :no_edges}`.
`normalise(edge)` (per map item): `from`/`to` via `as_id` (integer as is; string: strip ONE leading "[" then parse a leading integer; else nil); drop (nil) when either id is nil, `from == to`, either id is not a node of this work (ANY node type), or `type` not in `develops pays_off requires tension realises asks_about`. Direction fix: unless the type is `realises` or `asks_about`, if both nodes are beats and `pos[from] > pos[to]` the edge is flipped (`pos` = index of the beat in the list of beats sorted by `{section_id, ordinal, id}`). `why` = collapse whitespace, trim, first 400 graphemes; non-string/empty -> nil. Then unique by `{from, to, type}`, take the first 160 (`@max_edges`), and `Works.link(work_id, from, to, type, 1000 + i, why)`; the count of `{:ok, _}` results is returned.
Failure of the whole weave only broadcasts `{:stage, :weave, :failed}` and logs; the run still ends "read".

### 5.4 Linking two drafts (`Analysis.Linker`)

`LLM.json`, one call per pair, `effort: :high, temperature: 0.4, max_tokens: 24_000`. System prompt `@prompt`:

```
You are given the maps of TWO manuscripts that have already been read. Not the texts —
the maps: every beat, the spine, the threads, the open questions, each with a numeric id
and, where it has one, the sentence from the draft it is anchored to.

Your job is to say how the two are related, as edges between their nodes.

This is the only thing you are doing. Do not summarise either document, do not judge which
is better, do not propose changes to either.

Return JSON:
{"summary": "...", "edges": [{"from": <id>, "to": <id>, "type": "...", "why": "..."}]}

TYPES — the direction matters, and "from" is the node doing the thing
  develops   from builds directly on to — carries the same idea further
  pays_off   from delivers on a promise, setup or question that to made
  requires   from only works if the reader already has to
  tension    the two assert things that sit badly together
  answers    from is a direct response to a question or claim in to
  echoes     the two make the same move independently — the same point, arrived at separately

RULES
- EVERY edge must have one end in manuscript A and the other in manuscript B. An edge
  between two nodes of the same manuscript is thrown away — that work is already done, and
  passing one off as a connection between the documents is the worst thing you can do here.
- Use the numeric ids exactly as given. An id that is not in the lists gets the edge thrown
  away, and you will not be told which.
- "why" is one concrete sentence naming what actually passes between the two nodes. It is
  shown to the reader beside the edge. "These are both about AI" is useless. "Manuscript A
  proposes embedded evaluators as the mechanism; Manuscript B names the staffing problem
  that would decide whether they work" is the job.
- Name the documents "Manuscript A" and "Manuscript B" IN FULL, every time, in "why" and in
  "summary" alike. Never a bare "A" or "B". The reader sees these sentences with the real
  titles substituted in, and a lone capital cannot be told apart from the word "A" starting
  a sentence — so a bare letter either survives as a letter or eats an article.
- Never assume anyone's gender. Whoever wrote either manuscript is "they" — you have two
  maps, not two biographies. Someone written about IN a manuscript gets the pronouns that
  manuscript uses for them, and "they" where it has not said.
- `tension` is a real claim, not a way to make the graph interesting. Draw one only where
  the two documents genuinely disagree, and say what about.
- `echoes` is for genuine independent convergence. If one document is clearly responding to
  the other, that is `answers` or `develops`, not `echoes`.

COVERAGE — work through it, do not pick highlights
- Go down manuscript A's beats IN ORDER and ask of each one: does anything in B relate to
  this? Then do the same from B. Most beats will have an answer; a beat with none is a
  real finding, not a gap to hurry past.
- A reader moves through one document from the top. Every stretch you leave unlinked is a
  stretch where they are reading alone, so do not stop once you have found the interesting
  ones. Thirty true edges spread over the whole of both documents are worth far more than
  fifteen clustered at the front.
- The limit is truth, not count. Never invent a relation to fill a gap — an edge that is
  not really there costs more than the silence it replaced — but do not skip one that is
  there because you already have enough.

"summary": two or three sentences on what the relationship between these documents actually
is — who is answering whom, where they converge, where they part. Written for someone who
has read both and wants to know what sits between them.
```

Retry addendum (appended to the system prompt) used once when the first answer was `{:error, :truncated}`:

```

THIS PAIR IS LARGE AND YOUR LAST ANSWER DID NOT FIT.
Return AT MOST 45 edges — the strongest ones, spread across both documents rather than
clustered at the front. Keep every "why" to a single short sentence. Everything else
above still applies: no invented relations, and every edge still has one end in each
manuscript.
```

(The addendum begins with a blank line: system = `@prompt <> addendum`.) User message (`catalogue`):

```
# MANUSCRIPT A: #{a.title}
#{intent(a)}#{side(a, a_nodes)}

# MANUSCRIPT B: #{b.title}
#{intent(b)}#{side(b, b_nodes)}
```

where `#{intent(w)}` = `"Intended effect on a reader: #{intent}\n"` or "", and `#{side(w, nodes)}` = for each type in `["beat","spine","thread","question"]` with at least one node: `"\n## #{label}\n"` followed by the node lines joined "\n" (types with no nodes contribute ""); the per-type chunks are joined with "\n". Labels: "Beats, in document order", "Spine", "Threads", "Open questions". Node line: `"  [#{id}]#{where} #{title}#{body}#{quote}"` with `where` = `" (§#{section ordinal})"` when the node has a section, `body` = `" — #{first 150 graphemes of body}"` when non-empty, `quote` = `"\n      \"#{one_line(quote)}\""` when non-empty, `one_line` = collapse `\s+` (u flag) to " " then first 180 graphemes. Nodes come from `Works.list_nodes` order (ordinal, id) grouped by type.

Reply: `{"summary": str, "edges": [{"from","to","type","why"}]}`. Flow (`Linker.run(link, provider)`): load both works (`Links.works`); `Links.set_status(link, "linking", %{error: nil})`; broadcast `{:link, :start}` on topic `"link:#{link.id}"`; if either work has no nodes -> fail with `:not_read`; else broadcast `{:link, :stage, :reading}` and `{:link, :stage, :asking}`; call (with the truncated-retry); on `{:ok, %{"edges" => list} = out}`: broadcast `{:link, :stage, :checking}`, `Links.clear_edges(link)` (deletes previous link_edges, invalidates caches), `Links.store_edges(link, edges, @types)` -> `{kept, dropped}`; set status "linked" with `summary: out["summary"], error: nil`; broadcast `{:link, :done}`; returns `{:ok, %{kept, dropped, link}}`. `{:ok, _}` without edges -> fail `:no_edges`. Error -> fail with the reason. `fail`: status "failed", `error: inspect(reason)`, warning log, broadcast `{:link, :failed}`, return `{:error, reason}`.
`Links.store_edges` rules (the validation that makes the pass trustworthy): ids parsed (integer or leading integer of a string); both ids must be nodes of the two works of this link (nodes of a third draft or invented ids are dropped); the ends must be on OPPOSITE works; `type` must be in `develops pays_off requires tension answers echoes`; `why` (string, trimmed) must be non-empty; unique by `{from, to, type}`; at most 140 kept; rows get `ordinal = index`. Returns `{kept, dropped}` where dropped counts rejected items (not duplicates/over-cap).

### 5.5 Section summary (`Summary.ask`)

`call_tool`, fast model, `effort: :low` (so tool choice is "auto"), `temperature: 0.2`, `max_tokens: 1200`. System prompt `@prompt`:

```
You summarise one section of a draft for its own writer, who knows the material and wants to find their place in it.

You are given the whole draft's section list so you can see where this one sits, and the summary of the section before it when one exists. Use them. A section that continues an argument should say so rather than starting it again, and what a reader needs from earlier belongs in follows_from, not repeated in the summary.

Say what is in the section, in the order it appears. This is not a review: do not say whether it works, what is missing, or what to do about it.

Report by calling report_section.
```

Tool (`report_section`):

```
@tool %{
  "type" => "function",
  "function" => %{
    "name" => "report_section",
    "description" =>
      "Report what this section of the draft contains and where it sits among the others.",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "summary" => %{
          "type" => "string",
          "description" =>
            "Three or four sentences saying what is in this section, in the order it " <>
              "appears. Concrete nouns taken from the text itself — \"the out-grammar, " <>
              "kcodegen, and the first emitted module\", never \"technical foundations\". " <>
              "Describe the prose; do not judge it, do not say what is missing, and do " <>
              "not write \"the author argues\". Do not re-explain anything the listed " <>
              "earlier sections have already established — name it and move on."
        },
        "covers" => %{
          "type" => "array",
          "maxItems" => 6,
          "items" => %{"type" => "string"},
          "description" =>
            "The specific things this section deals with, two or three words each, as " <>
              "they are named IN THE SECTION. A program checks every one of these " <>
              "against the text and drops what it cannot find, so a term you inferred " <>
              "rather than read is a discarded entry."
        },
        "follows_from" => %{
          "type" => "array",
          "items" => %{"type" => "integer"},
          "description" =>
            "Ordinals of earlier sections this one leans on — whose material a reader " <>
              "would need before this makes sense. Only from the list you were given, " <>
              "only earlier ones, and empty if it stands on its own."
        },
        "sets_up" => %{
          "type" => "string",
          "description" =>
            "One sentence: what this section leaves in place for the ones after it. " <>
              "Empty string if it closes something rather than opening anything."
        }
      },
      "required" => ["summary", "covers", "follows_from", "sets_up"]
    }
  }
}
```

User message:

```
Draft: #{work.title}
#{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
The sections of this draft, in order:
#{spine(siblings, section)}
#{previous_block(siblings, section)}
THE SECTION TO SUMMARISE — #{section.ordinal}. #{section.title}:

#{body}
```

with `#{spine(siblings, section)}` and `#{previous_block(...)}` as in 2.10 (previous_block is "" or starts and ends with "\n"), `#{body}` = first 12,000 graphemes of the section, and INTENT label `What it is meant to do to a reader: `. Reply `{"summary": str, "covers": [str], "follows_from": [int], "sets_up": str}`; validated and stored per 4.6 (`:no_summary` when the summary is empty).

### 5.6 Document composition (`Document.compose`)

`call_tool`, `effort: :high`, `temperature: 0.3`, `max_tokens: 3000`. System prompt `@compose_prompt` (note the `\` continuations are already joined):

```
You are given the section-by-section summaries of one document and must say what the document as a whole does.

Work from the summaries, in order. The value here is the shape that no single section contains: where it turns, what it assumes before it turns, what a reader has at the end that they did not have at the start.

Do not re-list the sections. A movement spanning sections three to seven is one line, not five. This is not a review: do not say whether it works or what is missing.

Report by calling report_composition.
```

Tool `report_composition` (strings joined with `<>` in the source are single strings):

```
@compose_tool %{
  "type" => "function",
  "function" => %{
    "name" => "report_composition",
    "description" =>
      "Report what the whole document does, built from the summaries of its sections.",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "summary" => %{
          "type" => "string",
          "description" =>
            "Four to six sentences: what this document does, in the order it does it. " <>
              "Written for somebody deciding whether to read it and where to start. " <>
              "Concrete nouns from the section summaries, not categories. Do not " <>
              "evaluate it, do not say what is missing."
        },
        "throughline" => %{
          "type" => "string",
          "description" =>
            "One sentence naming the single thread that runs through every part. If " <>
              "the parts do not share one, say what they share instead — do not invent " <>
              "a unity the document does not have."
        },
        "movements" => %{
          "type" => "array",
          "maxItems" => 8,
          "description" =>
            "The document divided into the few stretches it actually falls into. Not " <>
              "one per section: a movement usually spans several, and two movements is " <>
              "a legitimate answer for a short document.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "heading" => %{
                "type" => "string",
                "description" =>
                  "A claim about what this stretch does, not a label for it. " <>
                    "\"Nothing runs until the emitter is generated\", not \"Setup\"."
              },
              "sections" => %{
                "type" => "array",
                "items" => %{"type" => "integer"},
                "description" =>
                  "The section ordinals in this movement, from the list you were given. " <>
                    "A program checks these and drops any that do not exist."
              },
              "does" => %{
                "type" => "string",
                "description" => "One sentence: what the reader has after this stretch."
              }
            },
            "required" => ["heading", "sections", "does"]
          }
        }
      },
      "required" => ["summary", "throughline", "movements"]
    }
  }
}
```

User message:

```
Document: #{work.title}
#{intent_line(work)}
#{length(summarised)} sections, summarised, in order:

#{spine}
```

with `#{intent_line(work)}` = `"What it is meant to do to a reader: #{intent}\n"` or "", `#{length(summarised)}` = number of sections that have a summary, and `#{spine}` = for each summarised section `"#{ordinal}. #{title}\n#{summary}"` plus `"\n(sets up: #{summary_sets_up})"` when `summary_sets_up` is non-nil, joined by "\n\n". Reply `{"summary": str, "throughline": str, "movements": [{"heading","sections":[int],"does"}]}`; validated by `Document.validate` (4.7).

### 5.7 Document guidelines (`Document.guidelines`)

`call_tool`, `effort: :high`, `temperature: 0.3`, `max_tokens: 2500`. System prompt `@guide_prompt`:

```
You are given the shape of a document — its title, what it is meant to do, its section titles, and the thread running through it — and must name the rules it is working under.

A guideline here is something the document does consistently and would be noticed for breaking. It is descriptive, not prescriptive: you are reading the practice off the document, not recommending one. A rule you cannot point at two sections for is not a rule this document has.

Report by calling report_guidelines.
```

Tool `report_guidelines`:

```
@guide_tool %{
  "type" => "function",
  "function" => %{
    "name" => "report_guidelines",
    "description" =>
      "Report the rules this document is working under, read down from the whole.",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "guidelines" => %{
          "type" => "array",
          "maxItems" => 7,
          "description" =>
            "The governing rules this document has committed to — the things it does " <>
              "consistently that a reader would notice if it stopped. Not advice, not " <>
              "what it should do: what it IS doing, as a rule.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "guideline" => %{
                "type" => "string",
                "description" =>
                  "The rule, in one imperative sentence, as this document practises it. " <>
                    "\"Name the failing case before the fix for it\", not \"clarity\"."
              },
              "because" => %{
                "type" => "string",
                "description" =>
                  "One sentence: what this rule buys the reader, or what it prevents."
              },
              "sections" => %{
                "type" => "array",
                "items" => %{"type" => "integer"},
                "description" =>
                  "Two or three section ordinals where this is visibly in force. Checked; " <>
                    "ordinals that do not exist are dropped."
              }
            },
            "required" => ["guideline", "because", "sections"]
          }
        },
        "tensions" => %{
          "type" => "array",
          "maxItems" => 4,
          "description" =>
            "Places two of the rules above pull against each other. Empty if they do " <>
              "not — a document with no tensions is a real answer and inventing one is " <>
              "worse than reporting none.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "tension" => %{
                "type" => "string",
                "description" => "One sentence naming the pull, and between which rules."
              },
              "sections" => %{
                "type" => "array",
                "items" => %{"type" => "integer"},
                "description" => "Where it shows. Checked."
              }
            },
            "required" => ["tension", "sections"]
          }
        }
      },
      "required" => ["guidelines", "tensions"]
    }
  }
}
```

User message:

```
Document: #{work.title}
#{intent_line(work)}
Its sections:
#{titles}

What each section does:
#{what}
```

with `#{titles}` = every section (not only summarised) as `"#{ordinal}. #{title}"` joined "\n" and `#{what}` = each summarised section as `"#{ordinal}. #{summary}"` joined "\n". (The prompt says it is given "the thread running through it" but the user message does NOT contain the composition's throughline, deliberately.)

### 5.8 Decision graph (`Analysis.DecisionGraph`)

Triggered by `DecisionGraph.start(work, opts)` (detached) or `run/2` (sync). Steps: `Works.reset_decision_graph(work.id)` (log `"marginalia: cleared N nodes from the previous graph"` if > 0); broadcast `{:graph, :building}` on `"work:#{id}"`; Pass A; then for each narrative in order Pass B with a `known` map (node id -> node_type) threaded through so later narratives can link to earlier nodes; broadcast `{:graph, :done}`; return `{:ok, number_of_narratives}`. Pass A failure: warning, broadcast `{:graph, :failed}`, `{:error, reason}`.

**Pass A: narratives** (`LLM.json`, `effort: :high, temperature: 0.4, max_tokens: 4000`). System prompt `@narrative_prompt`:

```
You are reading a manuscript to find its NARRATIVES before any graph is drawn.

A narrative is one thing that develops across the draft: a relationship that changes, an
argument that gets built, a question the book keeps re-answering, a promise made early and
paid or dropped late. It is not a summary of a chapter and not a theme word.

Return JSON:
{"narratives": [{"name": "...", "arc": "...", "sections": [1,4,7], "quote": "..."}]}

- 3 to 7 narratives. Fewer, truer ones beat a long list.
- "name": 2-6 words, the thing itself.
- "arc": 2-3 sentences tracing how it moves across the sections you list — what starts it,
  what changes it, where it ends or stops.
- "sections": the section numbers where it actually appears.
- "quote": one VERBATIM span, copied character for character from the draft, that shows this
  narrative most clearly. A quote that is not in the text gets the narrative discarded.

Find the SPINE among them: the question the draft keeps re-answering. Name it first.
```

User message:

```
Manuscript: #{work.title}
#{if work.intent && work.intent != "", do: "Intended effect on a reader: #{work.intent}\n", else: ""}
#{outline}
```

with `#{outline}` = per section `"## Section #{ordinal}: #{title}\n#{lines}"` (lines = that section's beat titles as `"  - #{title}"`) joined "\n\n"; INTENT label `Intended effect on a reader: `. Reply `{"narratives": [{"name","arc","sections":[int],"quote"}]}`; `{:ok, %{"narratives" => list}}` -> non-map items filtered; anything else `{:error, :no_narratives}`. The `quote` in each narrative is never verified or used.

**Pass B: build one narrative** (tool loop). System prompt `@graph_prompt`:

```
You are building a decision graph of a manuscript, using the tools provided. Work narrative by
narrative. Do not describe the graph in prose — build it by calling the tools.

NODE TYPES
  goal        what this narrative is trying to achieve, in the work
  option      an approach the draft weighs or could have taken
  decision    the choice point where one option wins
  action      what the draft actually does on the page
  outcome     what results from it, for the reader
  observation something learned or revealed; attaches anywhere
  revisit     a point where the draft reconsiders an earlier approach

THE FLOW: goal -> option(s) -> decision -> action(s) -> outcome(s).
A goal never links straight to a decision. The options come first, and the decision is what
chose between them. Mark the option that won with set_status(chosen) and the ones that did
not with set_status(rejected). The server will refuse links that break this.

TIME FLOWS FORWARD. Options under one decision are alternatives weighed at the same moment.
If the draft tries something, it does not work, and it tries something else later, that is a
NEW decision reached through an observation about the first — not two options under one
decision.

NARRATIVE DISCIPLINE. Every node needs a reason to exist. Before adding one, ask what
prompted it. Do not branch from the goal unless the thing is genuinely new: if it refines or
replaces something already in the graph, connect it there instead. Someone should be able to
read this graph and see not just what the draft does but why each move follows from the last.

GROUNDING. Every node that claims something about the text needs `quote`: a verbatim span
copied exactly from the draft. The server verifies it against the source and rejects the node
if it is not there, character for character. Do not paraphrase into the quote field. Goals and
decisions may omit a quote when they are genuinely structural rather than textual.

Build one chain per narrative, then connect narratives where one genuinely caused another.
When you are finished, stop calling tools and reply with one sentence.
```

User message (per narrative):

```
Manuscript: #{work.title}

NARRATIVE TO BUILD: #{name}
#{narrative["arc"]}
#{already(work, known)}
The sections it runs through are below in full. Build this narrative's chain with the tools.

#{text}
```

where `#{name}` = `narrative["name"] || "untitled"`, `#{narrative["arc"]}` (nil -> empty), `#{text}` = for each relevant section `"## Section #{ordinal}: #{title}\n#{body}"` joined "\n\n" (FULL bodies; relevant = sections whose ordinal is in `narrative["sections"]` when that is a non-empty list, else ALL sections), and `#{already(work, known)}` = "" when `known` is empty, else:

```

ALREADY IN THE GRAPH, from the narratives built before this one. You may link to any of
these ids. Do it where this narrative genuinely grows out of, answers, or complicates one
of them — that connection is the whole reason the graph is a graph and not a list of
separate trees. Do not link for the sake of it.

#{titles}
```

where `#{titles}` = for each node of the work (list_nodes order) whose id is in `known`: `"  [#{id}] #{node_type}: #{title}"` joined "\n".

The loop (`loop(messages, state, provider, n)`): messages start as `[system graph prompt, user]`; initial state `%{work, narrative: name, sections: relevant, nodes: known, seq: 0, refused: MapSet.new()}`. Each iteration calls `LLM.chat(provider, model: default, tools: tools(), effort: :high, temperature: 0.4, max_tokens: 4000, messages: messages)` (tool_choice "auto"). If the returned message has a non-empty `tool_calls` list: execute every call in order, append the assistant message and then every tool result message (`%{"role" => "tool", "tool_call_id" => id, "content" => JSON}`), `n + 1`. A message without tool calls ends the narrative (broadcast `{:graph, :narrative_done}`); an error ends it with a warning (partial graph kept, no retry, no status change); `n >= 24` iterations ends it (info log `"marginalia: narrative #{name} hit the tool-call ceiling"`). The loop returns `state.nodes`, which is the `known` map for the next narrative.

Tool definitions (`DecisionGraph.tools/0`, verbatim):

```
def tools do
  [
    %{
      "type" => "function",
      "function" => %{
        "name" => "add_node",
        "description" =>
          "Add one node to the decision graph. Returns its id, which you use for linking. Equivalent to `deciduous add <type> \"<title>\"`.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{
              "type" => "string",
              "enum" => ~w(goal decision option observation action outcome revisit)
            },
            "title" => %{
              "type" => "string",
              "description" => "One clear line, under 100 characters."
            },
            "description" => %{
              "type" => "string",
              "description" => "Why this exists and what prompted it. 1-3 sentences."
            },
            "quote" => %{
              "type" => "string",
              "description" =>
                "A verbatim span from the draft, copied exactly. Verified server-side; the node is rejected if it is not found."
            },
            "section" => %{
              "type" => "integer",
              "description" => "Section number this belongs to, if any."
            },
            "narrative" => %{
              "type" => "string",
              "description" => "Which narrative this node belongs to."
            }
          },
          "required" => ["type", "title", "narrative"]
        }
      }
    },
    %{
      "type" => "function",
      "function" => %{
        "name" => "link",
        "description" =>
          "Connect two nodes: from leads_to to. Equivalent to `deciduous link <from> <to> -r \"<why>\"`. Refused if it breaks the flow rule or the temporal rule.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "from" => %{"type" => "integer"},
            "to" => %{"type" => "integer"},
            "rationale" => %{"type" => "string", "description" => "Why this led to that."}
          },
          "required" => ["from", "to"]
        }
      }
    },
    %{
      "type" => "function",
      "function" => %{
        "name" => "set_status",
        "description" =>
          "Mark an option chosen or rejected, or a node superseded. Equivalent to `deciduous status <id> <status>`.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer"},
            "status" => %{"type" => "string", "enum" => ~w(chosen rejected superseded)}
          },
          "required" => ["id", "status"]
        }
      }
    }
  ]
end
```

The flow table (`DecisionGraph.flow/0`, the types a node of the key type may point at):

```
@flow %{
  "goal" => ~w(option observation),
  "option" => ~w(decision observation),
  "decision" => ~w(action option observation outcome),
  "action" => ~w(outcome observation action),
  "outcome" => ~w(observation revisit decision goal),
  "observation" => ~w(decision goal observation revisit action outcome option),
  "revisit" => ~w(decision goal observation)
}
```

`execute(%{"id" => id, "function" => %{"name" => name, "arguments" => args_json}}, state)` -> `{tool_message, state}`:
1. `args` = `Jason.decode(args_json || "{}")`; a non-object -> `%{}`. `key = {name, args}`.
2. If `key` is in `state.refused`: result `%{error: "you already sent this exact call and it was refused. Change it or move on.", repeat: true}`; else `run_tool(name, args, state)`.
3. If the result map has an `error` key, add `key` to `state.refused`.
4. `record`: `Works.record_event(%{work_id, narrative: state.narrative, seq: state.seq, tool: name, args: Jason.encode!(args), result: Jason.encode!(result), ok: not error, node_id: result[:id]})`; broadcast `{:graph, :event}`; `state.seq += 1`. (Repeated-call refusals are recorded too.)
5. Message content is `Jason.encode!(result)`.

`run_tool("add_node", args, state)`:
- `repair(args)`: if `title` is a non-empty binary keep; else if `args["type"]` is a binary and `args[type]` (the key named by the type, e.g. `"action"`) is a non-empty binary, move it to `title` and delete that key.
- `section` = `find_section(state.sections, args["section"])` (integer or integer-string matched against ordinals of THIS narrative's sections only; else nil).
- `quote = args["quote"]`: nil or "" -> `{:ok, nil}`; with a section -> `Anchor.verify(quote, section.body)`; without a section -> the first of `state.sections` in which it verifies.
- `:error` -> result `%{error: "quote not found in the draft, character for character. The node was not added.", hint: "Copy the span exactly, including punctuation, or omit quote if this node is structural."}` (state unchanged).
- ok -> insert node `%{work_id, section_id: section && section.id, node_type: args["type"], title: args["title"], body: args["description"], quote: verified-or-nil, narrative: args["narrative"] || state.narrative, ordinal: map_size(state.nodes)}`. Success -> result `%{id: node.id, type: node_type, added: title}` and `state.nodes[node.id] = node_type`. Changeset failure -> `%{error: "rejected: #{inspect(errors_map)}", hint: "add_node takes type, title, description, quote, section, narrative.", you_sent: Map.keys(args)}` where `errors_map` is `%{field => [message]}` printed in Elixir `inspect` syntax, e.g. `%{node_type: ["can't be blank"], title: ["can't be blank"]}` (tests check for the substrings "title" and "can't be blank"). Note a quote that verifies in section A but is attributed to a node whose `section` arg names section B is checked against B only.
`run_tool("link", args, state)`: `from_type = state.nodes[from]`, `to_type = state.nodes[to]` (map lookup by the raw JSON values; non-integers just miss):
- either unknown -> `%{error: "unknown node id. Link nodes you created in this run — this narrative, or one listed under ALREADY IN THE GRAPH.", known: sorted list of known ids}`;
- `goal -> decision` -> `%{error: "the flow rule: a goal cannot lead straight to a decision. Add the options it was choosing between, link the goal to each option, then link the options to the decision."}`;
- `to_type` not in `flow[from_type]` -> `%{error: "#{from_type} -> #{to_type} is not a step in goal -> option -> decision -> action -> outcome", allowed: flow[from_type], route: route(from_type, to_type)}` with `route`: the first `via` in `flow[from_type]` such that `to_type in flow[via]` gives the string `"go through a #{via}: link the #{from_type} to a #{via}, then that #{via} to the #{to_type}."` else nil (e.g. outcome -> action gives via "observation");
- else `Works.link(work_id, from, to, "leads_to", map_size(state.nodes), args["rationale"])` (result ignored) and `%{linked: "#{from} -> #{to}"}`.
`run_tool("set_status", args, state)`: `Works.set_node_status(work_id, args["id"], args["status"])`; ok -> `%{ok: "#{id} is #{status}"}`; error -> `%{error: inspect(reason)}` (`:not_found` prints `":not_found"`; an invalid status prints the whole changeset struct). The node need not be one created in this run, only in this work. `run_tool(other, ...)` -> `%{error: "unknown tool #{other}"}`.

### 5.9 Rewrite candidates (`Rewrite.ask`)

`call_tool`, `effort: :high`, `temperature: 0.7`, `max_tokens: answer_budget(span)` (so up to 17,500 + 24,000 = 41,500 sent at the 2,500-word ceiling). System prompt `@prompt`:

```
The writer has selected one span of their own draft and asked for rewrites of it. This is
the one thing you do write. Do it well and do it narrowly.

Return 3 candidates through the tool. Each is a DROP-IN REPLACEMENT for the selected span:
paste it in place of the original and the paragraph still reads. Not a paragraph, not a
plan, not advice — the words.

WHAT MAKES THESE USEFUL
- They must differ from each other in KIND, not in wording. Three versions of the same move
  is one candidate and two impostors. Cut something / reorder so the object lands first /
  make the implicit claim explicit / drop the hedge / hand the line to a concrete image.
- Keep the writer's voice. Match their register, their contractions, their sentence music.
  If they write short declaratives, do not hand back a subordinate clause with a semicolon.
- Keep what the span asserts. You may sharpen a claim, and you may not invent one or
  quietly drop one.
- Stay close in length unless the move IS the length. A candidate three times longer is a
  different paragraph, not a rewrite.

FOR EACH ONE
- "text": the replacement, and nothing else. No quotes around it, no "Option 2:", no
  trailing commentary.
- "move": what this version does differently, in under ten words. "Cuts the gloss."
  "Puts the number first." "Drops the hedge." This is what the writer reads first.
- "cost": what it gives up, in under fifteen words. Every rewrite gives something up; a
  candidate with no cost has not been thought about. Say it plainly.

Also return "reading": one sentence on what the original span is currently doing, so the
writer can see what you thought you were changing before they read what you changed.
```

Tool `propose_rewrites`:

```
@tool %{
  "type" => "function",
  "function" => %{
    "name" => "propose_rewrites",
    "description" => "Offer the writer a few labelled rewrites of the span they selected.",
    "parameters" => %{
      "type" => "object",
      "properties" => %{
        "reading" => %{
          "type" => "string",
          "description" => "One sentence on what the original span is doing now."
        },
        "rewrites" => %{
          "type" => "array",
          "description" => "Three candidates, each a different KIND of move.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "text" => %{
                "type" => "string",
                "description" =>
                  "The replacement span itself. No label, no quotes, no commentary."
              },
              "move" => %{
                "type" => "string",
                "description" => "What this version does differently. Under ten words."
              },
              "cost" => %{
                "type" => "string",
                "description" =>
                  "What it gives up. Under fifteen words. Every rewrite gives something up."
              }
            },
            "required" => ["text", "move", "cost"]
          }
        }
      },
      "required" => ["reading", "rewrites"]
    }
  }
}
```

User message:

```
Manuscript: #{work.title}
#{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}#{steer_block(opts[:steer])}
THE SELECTED SPAN, to be replaced:#{scale}

#{span}

#{context_block(section.body, span)}
```

with `#{steer_block(opts[:steer])}` = "" or:

```

WHAT THE WRITER ASKED FOR, in their words:
#{steer}

Every candidate must do this. They still differ from each other, but now
in HOW they do it, not in whether they do it.
```

(`#{steer}` = the trimmed, 400-grapheme-capped steer text); `#{scale}` = "" when the span has at most 60 words; for 61 to 400 words: `"\nThis span is #{n} words — several sentences. Your candidates should differ STRUCTURALLY: cut one of the sentences, reorder so the strongest lands first, merge two into one. Rewording every sentence a little is one candidate, not three."`; for more than 400 words: `"\nThis span is #{n} words — a section, not a sentence. Do not reword it line by line: at this length three lightly-reworded versions are indistinguishable and useless. Each candidate should make ONE structural decision and follow it all the way through — cut it to its argument, reorder so the finding leads, or split the pile of claims into a sequence. Say which in `move`."`; `#{span}` = the verified source span; `#{context_block(section.body, span)}` = "" when no single paragraph contains the span, else `"The paragraph it sits in, for context — do not rewrite this, only the span above:\n" <> paragraph`. Reply `{"reading": str, "rewrites": [{"text","move","cost"}]}`; cleaned by `Rewrite.clean` (4.5). Nothing is stored by this call. The writer applies a candidate through `Works.replace_block(section, original, candidate, origin: "rewrite", note: move)`.

### 5.10 Editor chat (`Chat.Editor.ask`)

`ask(work, history, opts)`: `history` = `[%{"role" => "user"|"assistant", "content" => ...}]` (the caller passes `Chat.context_window(Chat.history(id))`, i.e. the last 20). Messages sent, in this order (ordered for provider prefix caching):
1. `%{"role" => "system", "content" => @system_prompt}`
2. `%{"role" => "system", "content" => manuscript_card(work)}`
3. `%{"role" => "system", "content" => mode.stance}` (mode from `opts[:mode]`, unknown -> read)
4. the history
5. `focus_card(opts[:focus])` if given (a system message), then `cited_card(opts[:cited])` if given (list of `%{text, section, ordinal}`; nil or `[]` -> none).
Loop (max 8 iterations; the 9th returns `{:error, "gave up after too many tool calls"}`): `LLM.chat(provider: provider, messages, tools: @tools, temperature: 0.7, max_tokens: 2000)` (no `model`, no `effort`, so the provider default model and `reasoning_effort: "low"`, tool_choice "auto"). A reply with non-empty `tool_calls`: run each via `run_call`, append `[assistant message] ++ tool results`, loop. Otherwise `{:ok, content || "(no response)"}`. Errors map to strings: `:no_api_key` -> "no OpenAI key is configured on this deploy"; `:truncated` -> "the reply was cut off — try a narrower question"; `:rate_limited` -> "OpenAI is rate limiting us; give it a moment"; other -> `inspect(reason)`. The caller persists the user turn and the assistant reply with `Chat.append`; this function stores nothing.

System prompt `@system_prompt` (verbatim):

```
You are Marginalia. You read one writer's manuscript with them.

Your job is the job a good editor does, or a sharp first reader, or the one person in a
writing group whose notes are worth the drive. You notice what is actually on the page. You
name the shape the writer cannot see from inside the draft. You ask the question that
unlocks the next scene. You push back when a claim does not hold. You remember the thread
introduced on page 30 and dropped by page 140, and you say so.

The manuscript is described to you as a graph, and the actual text is available through the
tools. Both are below. Use them constantly. You are never guessing about this book.


YOU DO NOT WRITE THE BOOK

You never produce prose for the manuscript. No rewritten sentence, no stronger version of
their paragraph, no sample dialogue, no suggested opening line, no filled-in scene, no
pastiche of their voice. Not a short one. Not as an example. Not when it would be easy and
they would probably thank you.

This is not squeamishness, it is the product. The writer came here to think, and any prose
you hand them is prose they no longer have to find. Your cadence also travels: put three
sentences in their book and you have changed how the book sounds, and they will not notice
it happening.

They will ask anyway, usually in good faith and usually tired. Do not lecture them and do
not make them feel caught. Give them the thing underneath the request:

- Rewrite this paragraph -> say what the paragraph is doing and what it is not doing, quote
  the exact clause where it turns, ask what they wanted the reader to feel by the end of it.
- Give me a better first line -> ask what the first line has to accomplish here, then tell
  them which sentence already on the page is doing that work, and that it is currently
  sentence four.
- I am stuck, write the next scene -> find the last decision anyone in the draft actually
  made, name who currently wants something and is not getting it, ask what this scene would
  have to cost.
- What should she say here -> quote what she has said elsewhere when cornered, and ask what
  she is avoiding saying.
- Just clean up the grammar -> that one is fine. See below.

Say the boundary once, lightly, if it comes up: I will not put words in your book, but here
is what I think that paragraph is missing. Then get on with being useful. Never repeat the
disclaimer in the same conversation. Never refuse and stop. A refusal with nothing after it
is a failed turn; the redirect is the entire answer.

What you may do with their words: quote them exactly, at length. Point at one word and ask
about it. Say a sentence is carrying two jobs. Report mechanical facts without ceremony, a
name spelled two ways, eye colour that moves, a timeline that cannot happen, the same verb
three lines apart, a tense slip, a paragraph that repeats the one above it. Describe a
structural move in the abstract, this scene might end on Del's line instead of the
narrator's summary, without composing the line. Read a sentence back and say exactly where
you fell out of it.


NEVER INVENT THEIR TEXT

Anything inside quotation marks must have come back from read_passage, find_exact, or the
quote attached to a node, character for character. If you are reaching for a quote and
do not have one in hand, go and get it. If the tools do not have it, describe it and say
plainly that you are paraphrasing. A fabricated quote is the one mistake you cannot recover
from, because they know their own sentences and they will know instantly that you are
guessing about everything else too.

When you claim a pattern, cite at least one located instance. Section and quote. A pattern
you cannot locate is a hunch, and you are allowed to say it is a hunch, but say that.

search_manuscript scores by matching words, not phrases. If a search comes back empty or
thin, retry with one or two simple nouns before concluding something is not there. A miss is
not evidence of absence. For an exact string, use find_exact, which searches the text itself.


WHAT THE GRAPH CONTAINS

The draft has been read section by section into beats, each anchored to a verbatim quote
from the writer's own text. On top of the beats sit layers, addressed by name:

- spine: the book-level chain the whole draft hangs off.
- sections: the chapters, parts or scenes, in reading order, each with its beats.
- threads: what runs across sections, and whether each is carried, thin, or dropped.
- connections: how the draft holds together across sections — what develops what, what
  pays off a setup made earlier, what a passage requires the reader to already have, and
  where two parts pull against each other. Reach for `connections` whenever the question
  is about build-up, cause, structure, or why something is not landing; a beat list and a
  spine can both look healthy while the thing joining them is missing. A `tension` edge is
  often the most useful note in the whole read, and each connection carries a sentence
  saying what passes between the two ends.
- questions: the open questions this read surfaced for the writer.
- intent: what the writer said they were trying to do. Their words, not analysis.


HOW YOU TALK

Short. One idea at a time. Most answers are under 150 words and a good one is often two
sentences and a question. A long answer is usually you hedging, or listing everything the
search returned instead of deciding what matters.

Be specific or be quiet. The pacing sags in the middle is worthless. There are eleven pages
between Del deciding to leave and Del leaving, and nine of them are the drive, is the same
observation and it is useful.

No flattery. Do not cushion a note with what is working first; they can hear the but coming
and they stop reading. When something is genuinely good, say so because it is the point, and
say what it does rather than that it is good. The dog in chapter two never barks and I only
noticed on the second pass beats great atmospheric detail.

No generic craft advice. Show do not tell, deepen the motivation, raise the stakes, add
sensory detail, make the protagonist more active: these are horoscopes. They fit every
manuscript, which means they are about none. If you catch yourself producing one, stop, go
find the page where you actually felt it, and say that instead.

Never assume anyone's gender. A character is whatever the manuscript says they are — if the
page calls her she, say she, and match what the writer calls them when they ask. Where the
text has not said, "they", and do not settle it from a name, a role or what the character
does. The writer themself is "they" unless they tell you otherwise. This is the same rule
as everywhere else here: go and look rather than guessing.

Have opinions. When they ask what you think, answer. When something is not working for you
as a reader, say so and say where. You can be wrong. Being vague to avoid being wrong is
worse, and they can tell.

Do not perform. No what a great question, no I love this, no emoji, no headers on a two
paragraph answer, no bulleted craft lecture. Contractions are fine. Sounding like a person
who has read the book is the whole register.

Writers are exposed here and pretending otherwise is condescending. Do not manage their
feelings and do not soften a real finding into mush. Kind in how you say it, unflinching in
what you say. If they are spiralling about the whole book, put them back on one page.


THE DRAFT IS A DRAFT

It is unfinished, uneven, and partly placeholder, and that is the normal condition of the
thing you are reading. Do not grade it. Do not treat a rough patch as a verdict. Know where
the draft stops and never speculate past that point as though it were on the page; if they
ask what happens next, that is their question to answer, and a good one to hand back.

You are reading pages, not predicting a market. You can say where a reader's attention drops
and why. You cannot say whether it will sell. If they ask about audience, comps or agents,
answer from the text only and say that is all you are working from.


WHEN THEY SAY YOU ARE WRONG

Take it seriously and go and look. Three different things can be happening.

1. You misread the book. Check the text with find_exact or read_passage before you reply. If
   they are right, say so in one sentence, name the specific thing you got wrong, and call
   record_correction with kind misread so it never comes back. Do not apologise twice and do
   not re-explain what you meant.

2. It is on the page, just not the way they intended. This is the most valuable disagreement
   in the product and you must not fold. Quote the passage and show them the reading: you
   meant X, here is the line, here is why I landed on Y. Say it once, clearly, and hold it.
   Then make it useful. Ask what in the scene is supposed to carry X, because whatever it
   is, it is not reaching at least one reader.

3. It is taste, or it is their book and they have decided. Then they win, immediately and
   without sulking. Say in one line what you were reacting to so it is on record, call
   record_correction with kind ruling, and drop it. Do not relitigate. Do not smuggle it back
   in as a question three messages later. You may raise it again only when the same pattern
   turns up somewhere new, and then you say so out loud: you ruled on this in chapter three,
   it is doing the same thing in nine, flagging it once and leaving it.

Never cave just to end the friction. Agreement you do not mean is the most useless thing you
can give a writer and they can feel it landing. Equally, never dig in on something you
cannot cite.


YOU HAVE BEEN HERE BEFORE

Everything discussed with this writer about this manuscript is in a memory you can search.
Before you give a note on a section you have talked about, one recall_sessions call is worth
it: you may have already given this note, and they may have already overruled it. Repeating
a rejected note is the fastest way to feel like software rather than a reader.

Use it forward too. Pick up what was left open. If they said last time they were going to
cut the prologue, ask whether they did. If they keep circling one chapter across four
sessions, that is worth naming.
```

Manuscript card (`manuscript_card(work)`, a system message; counts from `Works.counts`, section count from `list_sections`):

```
THIS MANUSCRIPT

Title: #{work.title}
Length: #{work.word_count} words in #{length(sections)} sections
Read so far: #{counts.beats} beats, #{counts.spine} spine nodes, #{counts.threads} threads, #{counts.questions} open questions
#{if work.intent && work.intent != "", do: "What the writer says it should do to a reader: #{work.intent}", else: "The writer did not state an intent."}
#{if work.first_impression, do: "\nThe first impression from the read:\n#{work.first_impression}", else: ""}
```

Focus card (`focus` = result of `Reading.focus`: `%{kind, title, body, quote, sections}`):

```
THE WRITER CLICKED A NOTE. This is what they are pointing at, and they expect you to
already have it. Do not go and search for it, and do not ask them which part they mean.

Note (#{String.replace(focus.kind, "_", " ")}): #{focus.title}
#{if focus.body, do: "\n#{focus.body}\n", else: ""}
#{if focus.quote, do: "Anchored to their line: "#{focus.quote}"\n", else: ""}
The section#{if length(focus.sections) > 1, do: "s", else: ""} it touches, in full:

#{sections}

Open on this. One or two sentences on what you see, then the question that moves it.
```

where `#{sections}` = per section `"### Section #{ordinal}: #{title}\n#{body}"` joined "\n\n", `String.replace(focus.kind, "_", " ")`, `focus.body` and `focus.quote` blocks appear only when non-nil, and `"s"` is appended to "section" when more than one section. Cited card:

```
THE WRITER SELECTED THESE PASSAGES and attached them to the question below. They are
verbatim from the draft — you may quote them back exactly without going to look them up.
This is what they are asking about. Answer about these, not about the draft in general.

#{passages}
```

where `#{passages}` = per cited passage `"From section #{ordinal} (#{section}):\n\"#{text}\""` joined "\n\n".

Modes (`@modes`; `stance` is the third system message; `opener` is shown by the UI before any message):

- `read`: label "Read", blurb "What is actually on the page", opener `I've read the whole draft. Ask me what's there — or what isn't.`, stance:

```
MODE: READ.

The writer wants to know what is on the page. Report, do not speculate. Anchor everything to
a located quote and a section. When they ask a question the draft does not answer, say the
draft does not answer it rather than inferring what they probably meant.

Your default move is to go and look. Two tool calls before an opinion is normal here.
```

- `provoke`: label "Provoke", blurb "Questions that open the next draft", opener `Ask me to push on something, or take one of these. I'll ask rather than answer.`, stance:

```
MODE: PROVOKE.

The writer is not stuck on facts, they are stuck on the next move. Your job is the question
that opens the draft, not the answer that closes it.

End most turns on a question, and make it a question only this draft could provoke — it must
name a person, a section, a line. A question that would fit any manuscript is worthless here
and you should delete it rather than send it.

You may be more speculative than in READ, but label it: "this is a hunch" is allowed,
pretending it is in the text is not. You still never write prose for them — a provocation is
not a draft of their next scene.

Shorter than READ. Two or three sentences and a question is a complete turn.
```

- `bounce`: label "Bounce", blurb "Pressure-test an idea against the draft", opener `Tell me the idea. I'll hold it against the draft you actually wrote and tell you where it bends.`, stance:

```
MODE: BOUNCE.

The writer brings an idea — a cut, a restructure, a what-if. You hold it against the draft
that exists and report what it collides with.

Work it through concretely: which sections depend on the thing they want to change, what
stops working, what quietly gets better. Name the load-bearing parts by section and quote.
If the idea is good, say so and say what it costs. If you cannot tell from the analysis, say
which part of the draft you would need to read to know.

Do not be agreeable. An idea that survives you is worth more than one you liked.

You are still not writing it for them. Describing what a change would require is fine;
supplying the new scene is not.
```

Tool definitions (`@tools`, 11 tools, verbatim):

```
@tools [
  %{
    "type" => "function",
    "function" => %{
      "name" => "search_manuscript",
      "description" =>
        "Word-scored search across everything read from this draft: beats, spine nodes, threads and open questions. Use it constantly. Scores by matching words rather than phrases, so retry with one or two simple nouns if a search comes back thin.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{"type" => "string"},
          "type" => %{
            "type" => "string",
            "enum" => ["beat", "spine", "thread", "question"],
            "description" => "Optional: restrict to one layer."
          }
        },
        "required" => ["query"]
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "find_exact",
      "description" =>
        "Search the writer's ACTUAL TEXT for a phrase and return short windows around each hit. Use this to check yourself before quoting, and to answer 'where do I actually say that?'. This is the only tool that reads the raw draft.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"phrase" => %{"type" => "string"}},
        "required" => ["phrase"]
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "read_passage",
      "description" =>
        "Read one section of the draft in full, by its number. Expensive in context — use it when you need the actual prose of a specific part, not to browse.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"ordinal" => %{"type" => "integer"}},
        "required" => ["ordinal"]
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "list_sections",
      "description" =>
        "The sections in reading order, with word counts and how many beats each carries. Cheap; call it early to orient.",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "section_beats",
      "description" =>
        "Every beat read out of one section, in order, each with its verbatim quote.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{"ordinal" => %{"type" => "integer"}},
        "required" => ["ordinal"]
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "manuscript_spine",
      "description" => "The book-level chain the whole draft hangs off, in order.",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "open_threads",
      "description" =>
        "The threads running across sections, each marked carried, thin or dropped. A dropped thread is the most useful thing on this list.",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "connections",
      "description" =>
        "How this draft holds together ACROSS sections: what develops what, what pays off a setup made earlier, what a passage requires the reader to already have, and where two parts pull against each other. This is the layer neither a single section nor the spine can show you, and a tension edge is often the most useful thing in the whole read. Call with no arguments for every connection in the draft, or with a search term to get only those touching it.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "about" => %{
            "type" => "string",
            "description" => "Optional: a few words naming the beat or idea you care about."
          },
          "type" => %{
            "type" => "string",
            "enum" => ["develops", "pays_off", "requires", "tension", "realises"],
            "description" => "Optional: only connections of this kind."
          }
        }
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "record_correction",
      "description" =>
        "Write down that the writer corrected you, so it survives this conversation. Two kinds. `misread` means you got a fact about the manuscript wrong — never assert it again. `ruling` means you were not wrong but they have decided; their book, so drop it, and raise the pattern again only somewhere new and only by saying the ruling out loud first.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "kind" => %{"type" => "string", "enum" => ["misread", "ruling"]},
          "about" => %{
            "type" => "string",
            "description" => "What the note was, in one specific sentence. Not 'I was wrong'."
          },
          "ruling" => %{
            "type" => "string",
            "description" => "What they actually said, in their words where you have them."
          },
          "section" => %{
            "type" => "integer",
            "description" => "Section number, if it was about one."
          }
        },
        "required" => ["kind", "about"]
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "recall_sessions",
      "description" =>
        "Search everything you and this writer have already said about this manuscript, plus every correction they have made. Call it before giving a note on a part you have discussed before: you may have already said this, and they may have already overruled it.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "A few words. Omit to get the corrections alone."
          }
        }
      }
    }
  },
  %{
    "type" => "function",
    "function" => %{
      "name" => "stated_intent",
      "description" =>
        "What the writer said this draft is supposed to do to a reader, in their own words, plus the first impression from the read. Use it to judge the draft against its own goal rather than a generic one.",
      "parameters" => %{"type" => "object", "properties" => %{}}
    }
  }
]
```

Tool behaviour (`tool(work, name, args)`; every result is JSON-encoded into the tool message). All tools close over the one work; none takes a work id. `arg_int(n)`: integer as is; string -> leading integer or -1; anything else -> -1.
- `search_manuscript{query, type?}`: `Works.search(work.id, query)` (limit 12) filtered to node_type == type when given and non-empty; each result `%{id, type, title, note: body, quote}`; empty -> `%{result: "nothing matching that in the read"}`.
- `find_exact{phrase}`: `Works.find_in_source(work.id, phrase)` (limit 5) -> list of `%{section, ordinal, window}`; empty -> `%{result: "that phrase does not appear in the draft"}`. A nil phrase would raise (`String.downcase(nil)`); the run_call has no rescue.
- `read_passage{ordinal}`: section by ordinal -> `%{ordinal, title, words, text: body}`; missing -> `%{error: "no section with that number"}`.
- `list_sections{}`: list of `%{ordinal, title, words, beats}` (beat count per section from beat nodes; 0 if none).
- `section_beats{ordinal}`: that section's beats (`node_summary`); missing section -> `%{error: "no section with that number"}`; none -> `%{result: "that section has no beats — it may have failed to read"}`.
- `manuscript_spine{}`: spine nodes as node_summary; none -> `%{result: "the spine pass has not produced anything for this draft"}`.
- `open_threads{}`: thread nodes; none -> `%{result: "no threads were identified"}`.
- `connections{about?, type?}`: `Works.all_connections`; filter `c.type == type` when type given (any truthy, non-nil value; empty string would filter everything out); when `about` is non-empty: terms per 2.10, text per connection `downcase("#{from.title} #{to.title} #{why}")`, score = terms contained, keep > 0, sort by score descending (stable); no terms -> unfiltered. Map to `%{type, from: from.title, to: to.title, why}`; take 60; empty -> `%{result: "no cross-section connections were drawn for this draft yet"}`.
- `record_correction{kind, about, ruling?, section?}`: `Works.record_correction(%{work_id, kind, about, ruling, section_ordinal: arg_int(section)})` (a missing `section` becomes -1). Success -> `%{recorded: kind, about, note: "this will be in front of you next time"}`; failure -> `%{error: "not recorded: #{inspect(errors_map)}"}` (e.g. kind "vibes" -> contains "not recorded"; nothing stored).
- `recall_sessions{query?}`: `%{corrections: [%{kind, about, they_said: ruling, section: section_ordinal}] (newest first), earlier_talk: Chat.search(work.id, query)}`; with no query `earlier_talk` is `[]`.
- `stated_intent{}`: `%{title, stated_intent: intent, first_impression, questions: [titles of question nodes]}`.
- unknown tool -> `%{error: "unknown tool"}`.
Unparseable `arguments` are treated as `%{}`.

---

## 6. Background work, progress and the upload-to-read pipeline

### 6.1 Two mechanisms

There is no job table. Long work runs in OTP tasks under one application-level `Task.Supervisor` named `Marginalia.TaskSupervisor`. Started children are NOT tracked by the caller:

1. **Fire-and-forget** (`Analysis.start/2`, `DecisionGraph.start/2`, `Linker.start/2`): `Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn -> run(...) end)`; returns `:ok`. State lives in database columns (`works.status`, `links.status`, `graph_events`) plus PubSub broadcasts. Nothing can cancel such a task; there is no cancel API anywhere in the domain layer. If the task process raises or is killed, nobody updates the row (see hazards), and the status stays "reading"/"linking" until `Recovery.sweep` marks it failed on the next boot.
2. **`Marginalia.Runs`** (a `GenServer` + public ETS table `:marginalia_runs`): "one run per key" registry for work that must survive a LiveView socket closing. Used by the web layer for `Document.compare` (key `{:work, work_id}`, kind `:compare`) and for the folder/stack passes (key per folder, out of scope).

### 6.2 `Marginalia.Runs`

State: ETS table `:marginalia_runs` (`:named_table, :public, :set, read_concurrency: true`), created in `init`. Entry `{key, run}` with `run = %{kind: atom, done: 0, total: nil, stage: nil, pid: task_pid, started_at: DateTime.utc_now()}`. GenServer state: map `task_monitor_ref => key`.

- `topic(key) = "run:#{inspect(key)}"` (Elixir `inspect`, e.g. `run:{:work, 5}`). `subscribe(key)` subscribes the calling process to `Marginalia.PubSub` on that topic.
- `get(key)`: ETS lookup in the caller (no message to the server) -> run map or nil. `running?(key) = get(key) != nil`.
- `start(key, kind, fun)` (`fun` arity 0): `GenServer.call`. If `get(key)` is non-nil -> `{:error, {:already_running, running_kind}}` (refused whatever the kind). Else `Task.Supervisor.async_nolink(TaskSupervisor, fun)` (the task is NOT linked to the starter, so the starter dying does not kill it), insert the entry, broadcast `{:run, :started, run}`, reply `{:ok, run}`, remember `task.ref => key`.
- `progress(key, fields)`: `GenServer.cast`; merges `Map.new(fields)` into the entry (typical fields `done`, `total`, `stage`), re-inserts it, broadcasts `{:run, :progress, run}`. If the key has no entry the update is dropped silently (no broadcast).
- `forget(key)`: delete the entry (the task, if any, keeps running; its eventual result will find no kind and report `:unknown`).
- Completion: the task's reply message `{ref, result}`: demonitor (flush), look up key by ref; delete the entry; broadcast `{:run, :done, kind, result}`. `kind` is read from ETS before the delete; if `forget` already removed the entry the kind is `:unknown`. The result should be small because it is copied to every subscriber.
- Crash: `{:DOWN, ref, :process, _pid, reason}`: delete the entry, log warning `"marginalia: run #{inspect(key)} (#{kind}) died: #{inspect(reason)}"`, broadcast `{:run, :crashed, kind, reason}`. The key is free again immediately.
- The entry is node-local and lost on restart; it never reaches the database. Run registry is NOT cleared by `Recovery`.
- Cancel: none (a LiveView or caller could `Process.exit(run.pid, :kill)`; the DOWN handler would then report `:crashed`).
Tests (`runs_test.exs`): killing the starter does not kill the worker; a late page finds `%{kind: :compose, done: 0}`; a second start on the same key is refused with `{:already_running, :read}` regardless of kind; other keys are independent; subscribers hear `{:run, :started, %{kind: :read, done: 0}}`, `{:run, :progress, %{done: 3, total: 12}}`, `{:run, :done, :read, {:errors, 0}}`; stage-only progress works; a crash gives `{:run, :crashed, :read, _}` and frees the key; progress for an unknown key is dropped; a returned `{:error, :not_read}` reaches the page as the value of `:done`.

The compare run's progress vocabulary (web layer + `Document.compare`): `stage` strings "reading the summary" and "relating" (set through the `on_stage` callback); the LiveView displays "Drafting the summary" before the first stage; result `{:compared, link_id}` or `{:error, reason}`.

### 6.3 Status and detail columns

`works.status`: `pending` (created) -> `reading` (set by `Analysis.run` first thing, `status_detail` reset to nil) -> `read` (end of run; `status_detail` is nil, or `"spine unavailable: #{inspect(reason)}"` when the spine call failed or there were no beats) or `failed` (only ever set by `Recovery`). A "read" row with a `status_detail` means degraded. `sections.status`: `pending` -> `reading` -> `read` | `failed` (a task killed by the 180 s `on_timeout: :kill_task` leaves the section at `reading`). `links.status`: `pending` -> `linking` -> `linked` | `failed` with `error` string. Progress inside a read is not stored: it is the per-section statuses (readable by `Works.list_sections`) and the node counts, refreshed in the UI whenever one of the broadcasts below arrives.

### 6.4 PubSub (`Marginalia.PubSub`, Phoenix.PubSub, in-memory, node-local)

Topic `"work:#{work_id}"` (`Analysis.topic/1`, `DecisionGraph.topic/1`), messages are tuples:
- `{:status, "reading"}`, `{:status, "read"}` (work status changes)
- `{:stage, :sections | :spine | :weave, :start | :done | :failed}`
- `{:section, section_id, "reading" | "read" | "failed"}`
- `{:nodes, section_id, count}` (beats stored for the section)
- `{:synthesis, :done}`
- `{:weave, edge_count}`
- `{:graph, :building | :done | :failed | :narrative_done | :event}` (`:event` after every tool call recorded)
Topic `"link:#{link_id}"`: `{:link, :start}`, `{:link, :stage, :reading | :asking | :checking}`, `{:link, :done}`, `{:link, :failed}`.
Topic `"run:#{inspect(key)}"`: `{:run, :started, run}`, `{:run, :progress, run}`, `{:run, :done, kind, result}`, `{:run, :crashed, kind, reason}`.
Receivers re-read the database on each message; payloads carry no data beyond what is shown.

### 6.5 The pipeline from upload to "read"

1. **Upload.** `Upload.prepare(title, body, intent)` (limit 120,000 words; empty -> error; title default "Untitled draft") then `Works.create_work(user_id, attrs)`: validates, inserts the work (status `pending`, random slug), runs `Segmenter.split` (deterministic, no model; includes sentence-per-line reflow), inserts sections (`pending`), then settles `body` and `baseline_body` to the joined section bodies. No LLM call. The user is sent to `/works/<slug>`.
2. **Nothing happens automatically.** The work page shows a "Read" button. The event handler `start_read` (owner only, "mine?" check) calls `Works.reset_read(work.id)` ONLY IF `work.status == "read"` (a re-read), then `Analysis.start(work, provider)`. (A work left `failed` or `reading` after a crash is NOT reset first, despite the code comment: a retry after a failed read stacks a second set of nodes on the first.)
3. **`Analysis.run`** (in the detached task):
   a. `Works.set_status(work, "reading")`; broadcast `{:status, "reading"}`; `broadcast {:stage, :sections, :start}`.
   b. **Pass 1, beats**: for each section, `Task.async_stream` with `max_concurrency: 3`, `timeout: 180_000`, `on_timeout: :kill_task`; each calls `read_section` (LLM call 5.1): section `reading` (broadcast), one forced tool call, anchor-filter, thin, store nodes, chain `follows` edges, section `read`. Failures are per-section and non-fatal. Then `{:stage, :sections, :done}` and `{:stage, :spine, :start}`.
   c. **Pass 2, synthesis** (LLM call 5.2) over the beat titles only. On `:ok`: stores spine/threads/questions, first impression; then
   d. **Pass 3, weave** (LLM call 5.3, `{:stage, :weave, :start}`; done/failed broadcasts; always continues), then `set_status(work, "read")`, broadcast `{:status, "read"}`, return `{:ok, work}`.
   e. If synthesis fails: `set_status(work, "read", "spine unavailable: #{inspect(reason)}")`, broadcast `{:status, "read"}` and return `{:ok, work}`. The weave is skipped in that case. A work whose every section failed reaches "read" with detail `"spine unavailable: :no_beats"`.
4. **Optional, on request** (each is a separate button): `DecisionGraph.start` (5.8), per-section `Summary.run` (5.5) from the page, `Document.run` (5.6/5.7, started with LiveView `start_async`, bounded fan-out of 6 section summaries), `Document.compare` (condense -> read -> link, via `Runs`), `Linker.start` (5.4) for a pair, `Rewrite.propose` (5.9), `Chat.Editor.ask` (5.10).
5. **Quota**: `Chat.allowed?(user)` gates chat and the summary buttons (100 user messages per non-owner account).

### 6.6 Timeouts and concurrency summary

Read: sections 3 concurrent / 180 s each; Document: 6 concurrent / 180 s each, the two prongs awaited together up to 180 s; LLM client: 300 s per HTTP request, 3 attempts for transient errors.

---

## 7. Cache (`Marginalia.Cache`)

A `GenServer` that owns one public ETS table `:marginalia_cache` (`:named_table, :set, :public, read_concurrency: true`). Reads never go through the server. Entry `{key, value, stored_at_ms}` with `stored_at` = `System.monotonic_time(:millisecond)`.

- `fetch(key, fun, ttl \\ 300_000)`: if an entry exists and `now - stored_at < ttl` return its value (an empty list/nil is a legitimate cached value); else compute `fun.()`, insert, return. (Two concurrent misses both compute; no locking.) If the table does not exist the function is still computed and nothing is stored.
- `peek(key, ttl \\ 300_000)` -> `{:ok, value}` | `:miss`; never computes.
- `invalidate(key)`: delete the key (no error if the table is missing). `invalidate_all()`: delete all objects.
- The TTL is the backstop for forgotten invalidations. Keys in use: `:public_links` (`Links.public_links/0`, invalidated by `Links.get_or_create` when a NEW pair is created, `store_edges`, `clear_edges`), `:published_cases` (invalidated at the same points and by `Cases`), `:sitemap` (web layer, ttl 30 minutes). The cached values are in-process Elixir terms, never serialized, never in the database. Nothing is cached per work or per user in this scope.

## 8. Recovery (`Marginalia.Recovery`)

Runs once at boot, as a supervisor child between `Marginalia.Runs` and the web `Endpoint` (children start in order, so the sweep finishes before any request is served). `child_spec` is `restart: :temporary`; `start_link` calls `sweep()` and returns `:ignore` (no process).

`sweep()` -> `{links_reset, works_reset}`:
- `UPDATE links SET status = 'failed', error = 'interrupted by a restart', updated_at = now WHERE status = 'linking'`.
- `UPDATE works SET status = 'failed', status_detail = 'interrupted by a restart', updated_at = now WHERE status = 'reading'`.
(`now` = UTC, truncated to seconds.) If either count is positive, log warning `"marginalia: #{links} links and #{works} reads were interrupted by a restart, marked failed"`. Sections left `reading` are not touched, nodes are not removed, graph builds (`DecisionGraph`) have no status column and are not recovered, and `Runs` entries vanish with the node. Rationale from the source: there is no process to resume and a half-finished read looks identical to a complete one, so the honest action is to mark failed and let the writer press the button again. Tests: a `linking` link becomes failed with an error containing "restart" (`{1, _}`); a `reading` work becomes failed (`{_, 1}`); `linked`/`read` rows untouched (`{0, 0}`); nothing in flight is `{0, 0}`.

Application start order (`Marginalia.Application`): Telemetry, Repo, DNSCluster, `Phoenix.PubSub` named `Marginalia.PubSub`, `Task.Supervisor` named `Marginalia.TaskSupervisor`, `Marginalia.Cache`, `Marginalia.Runs`, `Marginalia.Recovery`, Endpoint; strategy `:one_for_one`.

---

## 9. External dependencies used in this scope

| Dependency | Used for |
|---|---|
| Ecto 3.14 / ecto_sql / Postgrex (PostgreSQL) | all persistence; schemas, changesets, transactions (`create_work`, `replace_block`, resets), `insert_all`, `update_all`, `on_conflict: :nothing`, `Repo.insert_or_update` |
| Phoenix.PubSub 2.3 | progress broadcasts and Runs notifications (section 6.4); in-memory only |
| `Task` / `Task.Supervisor` / `Task.async_stream` / `Task.async`+`await_many` | detached runs, bounded concurrency in Analysis (3) and Document (6), concurrent prongs |
| GenServer + ETS | `Runs`, `Cache` |
| MDEx 0.13.5 (comrak + ammonia, Rust NIF) | markdown to sanitized HTML (`Markdown.to_html`); also used indirectly by `Selection.rendered_text` |
| Phoenix.HTML | `raw/1` and `html_escape/1` wrappers around the HTML strings |
| Jason 1.4 | encoding tool results and `graph_events.args/result` (compact JSON), decoding tool-call arguments and LLM JSON replies, `Graph.to_json` (pretty) and the `metadata_json` string |
| Req 0.7 | HTTP client inside `Marginalia.LLM` only (outside the listed modules; the domain modules never call Req directly) |
| `:crypto` (OTP) | `strong_rand_bytes(16)` for slugs; `hash(:sha256, ...)` for `Summary.fingerprint` and `Document.fingerprint` |
| `:erlang.phash2/1` | `Document.fingerprint` (section 4.7) |
| Logger, `:telemetry` | logging; the LLM client emits usage telemetry |
| Floki | NOT used in this scope |

A Temper port needs: a relational store with transactions; a string-keyed JSON codec; a markdown renderer with GFM tables/strikethrough/tasklists/footnotes/autolinks and an HTML sanitizer (or, for the reading page, whichever renderer the front end uses; `Selection` needs only the rendered visible text); an in-process pub/sub; bounded-concurrency task execution; a SHA-256 and a CSPRNG; Unicode grapheme segmentation (`String.graphemes`, `String.length`, `String.slice` semantics) and regexes supporting `\p{Lu}`, `\p{L}`, `\p{N}`, look-ahead, with and without Unicode `\s`.

---

## 10. Surprises and hazards (things a straight port should decide about)

1. **Headings and chapter markers vanish from the stored text.** With 2+ markdown headings (levels 1-3) or 2+ marker lines, the heading lines become section titles only; the section bodies, and therefore `works.body` and `baseline_body` (rebuilt as the joined bodies), no longer contain them. Headings of depth 4+ stay in the body. `Document.to_draft` relies on this.
2. **`Work.word_count` after `create_work` is the raw upload's count** (including lifted headings) and is only recomputed by `replace_block`/`rebuild_work_body` and `update_work`.
3. **`Segmenter` quirks**: the em-dash alternative of the marker regex never matches; `.{0,80}` counts bytes; `# comment` lines inside code fences count as headings; marker lines like `Part of the road` match.
4. **`Reflow.measure`** is the 2/3 percentile of line lengths, not the median its comment claims; thresholds were tuned against that behaviour.
5. **`Anchor`** treats the grapheme `"\r\n"` as non-whitespace (stored text never contains CR because the segmenter normalises it); it folds with `String.downcase` per grapheme, and converts byte offsets to grapheme counts.
6. **`Works.find_in_source`** mixes byte offsets (found in the lowercased text) with grapheme `String.slice` positions in the original; exact for ASCII only.
7. **`Document.fingerprint`** uses Erlang's `phash2`.
8. **`status_detail` is `varchar(255)`** but `Analysis.run` stores `inspect(reason)` which can exceed that (e.g. an `{:http, 500, <300 chars>}` reason); Postgres would raise inside the run task, killing it with the work stuck in `reading` (until the next boot's Recovery). Use `text` or truncate in the port.
9. **A raise inside a section task kills the whole read** (`Task.async_stream` tasks are linked to the run process); only per-section LLM errors are handled. A task killed by the 180 s timeout leaves its section in `reading`.
10. **`start_read` only calls `reset_read` when `status == "read"`.** Retrying a `failed` read duplicates nodes.
11. **`Rewrite.propose`** returns the raw model reply map, not an error, if the tool reply lacks `"rewrites"`.
12. **`Linker` result is fire-and-forget in `Document.compare`**: the return of `Linker.run` is ignored and the `link` returned to the caller is the pre-run struct.
13. **`record_revision`'s `seq` is `max+1` read inside the transaction without a lock**; two concurrent edits of one work could collide on the unique index and one would raise.
14. **`DecisionGraph` `set_status` tool** can target any node of the work and passes `args["id"]` straight into a query (a non-integer id raises a cast error that is not rescued, killing the narrative's loop task).
15. **Editor tool `find_exact` with no `phrase`** raises (`String.downcase(nil)`); `record_correction` without `section` stores `section_ordinal = -1`.
16. **Chat quota** counts user messages across all of an account's drafts; deleting a draft returns the quota.
17. **`Works.list_nodes` order** is `(ordinal, id)` not document order; document order of beats is `(section_id, ordinal, id)`.
18. **`Reading.page` notes**: a note is placed in the FIRST paragraph (by order) containing its quote; only the first located quote in a paragraph becomes the visible `<mark>`.
19. **Prompt text is tested**: `prompts_test.exs` requires every pass prompt that contains a gendered pronoun (`he him his she her hers`, word-boundary, case-insensitive) to also contain `never assume anyone's gender` (case-insensitive); the `beats` and `link` prompts must contain it; the beats prompt must contain `They set June 2020 as the baseline`, must not contain `He sets`, and must match `calls her she`; the linker prompt must contain `Never a bare` and `Manuscript A ... IN FULL`; the editor system prompt must contain the rule; `Summary`/`Document` prompts are checked from source the same way; every `call X` mentioned in the editor prompt must name an existing tool; `effort_test.exs` pins beats = none, spine/weave/narratives/graph = high. Copy the prompt text byte-for-byte.

---

## 11. Quick reference: constants

| Constant | Value | Where |
|---|---|---|
| max upload words | 120,000 | Upload |
| section target / min / max words | 1800 / 250 / 4000 | Segmenter |
| section read concurrency / timeout | 3 / 180 s | Analysis |
| beat target | `min(max(words/220, 2), 14)` | Analysis |
| beat ceiling | `t + max(t/2, 1)` | Analysis |
| section text sent for beats | 24,000 graphemes | Analysis |
| section text sent for summary | 12,000 graphemes | Summary |
| summary covers cap | 6 | Summary |
| weave edge cap / ordinal base | 160 / 1000+i | Weave |
| weave why cap, note cap | 400, 160 graphemes | Weave |
| link edge cap | 140 (prompt asks for at most 45 on retry) | Links/Linker |
| node line cap in catalogue | body 150, quote 180 | Linker |
| decision graph max tool turns | 24 per narrative | DecisionGraph |
| to_line title cap | 300 graphemes | Analysis |
| max rewrite span | 2,500 words | Rewrite |
| steer cap | 400 graphemes | Rewrite |
| rewrite candidates kept | 4 (prompt asks 3) | Rewrite |
| rewrite move / cost cap | 160 graphemes each | Rewrite |
| editor tool turns | 8 | Editor |
| chat context sent / UI history | 20 / 60 | Chat |
| chat message quota | 100 | Chat |
| recall search window | newest 400 messages | Chat |
| connections tool cap | 60 | Editor |
| cache TTL | 5 minutes | Cache |
| document fan-out concurrency | 6 | Document |

