#!/usr/bin/env bash
# 80_stacks.sh: the Methods pages. /stacks (the list), /stacks/new (the import form),
# /stacks/:id (a folder and the six passes that read it), /stacks/:id/:ordinal (one step) and
# /stacks/:id/story (the telling).
#
# Source tests (notes/tests.md part 8): stack_routes_test (3) and stack_run_test (10), plus the
# behaviours of notes/web-works-stacks.md sections 4 to 7. public_reading_test, reading_owner_test
# and tour_test of the same listing belong to the public and reading pages, not to these.
#
# Folders and drafts are seeded with sqlite3 in the app's database (the pages that make them,
# /works, are another group); users register and log in through the real pages.
#
# stack_run_test held a pass with a function the test controlled. Here a pass is a forked job, so
# there are two kinds of test:
#   * "seeded": a row in `runs` as `runsStart` and a job would leave it (running, 4/12, `read`)
#     and no job at all, so the page can only show what the row says. These are the counters, the
#     sentences, the disabled buttons, the refusals, the crash.
#   * "real": the button is pressed and the job runs against fake_llm, whose replies are
#     fixtures/llm/"You read one document out of an ordered series.report_step.json" (the needle is
#     a phrase of the pass's system prompt) and its siblings for outline_story, write_part and
#     propose_links. A folder whose drafts say FAKE_LLM_SLOW answers two seconds late, which holds a
#     pass open long enough to press a second button during it.
#
# Not asserted: the import itself (it fetches from api.github.com; the Temper tests of the importer
# and of pages_stacks drive it against a fake), the open-page-follows-a-pass-it-did-not-start case
# as a browser would see it (nothing polls an idle page; the poll after the row appears is asserted).
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

PASS='hello world!'
sq() { sqlite3 -cmd '.timeout 5000' "$MARGINALIA_DB" "$@"; }

command -v sqlite3 >/dev/null 2>&1 || { skip "stacks: needs the sqlite3 command to seed folders and drafts"; exit 0; }

# poll PATH: the refetch blimp.js makes while a [data-poll] element is on the page
poll() { _curl GET "$1" -H 'x-requested-with: blimp' -H 'accept: application/json'; }

# seed_folder USER_ID NAME [PARENT_ID]: prints the id
seed_folder() {
  if [ -n "${3:-}" ]; then
    sq "INSERT INTO folders (name, user_id, parent_id) VALUES ('$2', $1, $3); SELECT last_insert_rowid();"
  else
    sq "INSERT INTO folders (name, user_id) VALUES ('$2', $1); SELECT last_insert_rowid();"
  fi
}

# seed_work USER_ID FOLDER_ID TITLE BODY [STATUS]: a draft in a folder, one section holding BODY
seed_work() {
  local slug="stacks-$RANDOM$RANDOM$RANDOM"
  sq "INSERT INTO works (user_id, title, body, word_count, slug, folder_id, status) VALUES ($1, '$3', '$4', 12, '$slug', $2, '${5:-pending}');
      INSERT INTO sections (work_id, ordinal, title, body, word_count) VALUES (last_insert_rowid(), 1, '$3', '$4', 12);"
}

# seed_step FOLDER_ID ORDINAL CAPABILITY: a step for the ORDINAL-th document of the folder
seed_step() {
  local w
  w="$(sq "SELECT id FROM works WHERE folder_id = $1 ORDER BY id LIMIT 1 OFFSET $(($2 - 1))")"
  sq "INSERT INTO stack_steps (folder_id, work_id, ordinal, capability, requires, lesson) VALUES ($1, $w, $2, '$3', '[]', 'Lesson $2.');"
}

# run_row FOLDER_ID STATUS PROGRESS DETAIL: the row `runsStart` and a job would leave
run_row() {
  sq "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at)
      VALUES ('stack:$1', '$2', '$3', '$4', NULL, datetime('now'), CASE WHEN '$2' = 'running' THEN NULL ELSE datetime('now') END);"
}

# wait_sql QUERY EXPECTED SECONDS DESC
wait_sql() {
  local i=0 n=$(($3 * 2)) got=""
  while [ "$i" -lt "$n" ]; do
    got="$(sq "$1")"
    [ "$got" = "$2" ] && { _ok "$4"; return 0; }
    sleep 0.5; i=$((i + 1))
  done
  _bad "$4" "expected '$2', last saw '$got' for: $1"
}

# every response body since ACC was emptied, so a flash that rode on an event reply or on a
# poll is found whichever came first
ACC="$T/acc"
: > "$ACC"
keep() { cat "$BODY_F" >> "$ACC"; }
assert_seen() { # TEXT DESC
  if grep -qF -- "$1" "$ACC"; then _ok "$2"; else _bad "$2" "never seen in any response since the pass began: $1"; fi
}

OWNER_MAIL="${OWNER_EMAIL:-bobbbygrayson@gmail.com}"
WRITER="stacks-writer$RANDOM@example.com"

# ============================ stack_routes_test ===============================
new_visitor writer
ensure_user "$WRITER" "$PASS"
WID="$(sq "SELECT id FROM users WHERE email = '$WRITER'")"

# test "the import page is its own page"
get /stacks/new
assert_status 200 "routes: /stacks/new is a page"
assert_contains "Import a stack" "routes: the import page says so"
assert_contains 'name="repo"' "routes: and has the repository field"
assert_contains 'name="token"' "routes: and has the token field"
assert_contains 'type="password"' "routes: the token is a password field"
assert_not_contains "data-poll" "routes: nothing is going on, so nothing polls"

# test "a folder id still reaches the folder"
get /stacks/999999
assert_status 303 "routes: a folder that is not there is not a page"
assert_redirect_to /stacks "routes: it sends the reader back to the list"
get /stacks
assert_contains "No such folder." "routes: and says why"
get /stacks/abc
assert_redirect_to /stacks "routes: a word where the id goes is the same redirect"

# test "the list is reachable"
get /stacks
assert_status 200 "routes: the list is reachable"
assert_contains "Methods" "routes: it is called Methods"
assert_contains "Nothing here yet. Put some drafts in a folder and it becomes readable." "list: with nothing in it, the empty state"
assert_contains "0 readable folders" "list: and the count"
assert_contains 'href="/import" class="mg-btn sm ghost ml-auto">Import many</a>' "list: the way to the bulk import"
assert_contains 'href="/stacks/new" class="mg-btn sm">Import a stack</a>' "list: and to the stack import"

# the literal pages are not shadowed by the ones with variables
get /stacks/new
assert_not_contains "No such folder." "routes: /stacks/new is not a folder called new"
get /stacks/1/story
assert_status 303 "routes: /stacks/:id/story is the telling, not step 'story' (which would be a 500)"

# a stranger is given a guest, and sees the same list
new_visitor stranger
get /stacks
assert_status 200 "list: a visitor may open it"
assert_cookie _marginalia_key "list: and is given a session"
assert_contains "0 readable folders" "list: and has nothing"

# ================================ the list ====================================
new_visitor writer
login "$WRITER" "$PASS"
F1="$(seed_folder "$WID" 'Phoenix 1.8')"
seed_work "$WID" "$F1" '1. A chapter' 'The first chapter says to start with a window and wait.'
seed_work "$WID" "$F1" '2. Another chapter' 'The second chapter builds the door on the window.'
FI="$(seed_folder "$WID" 'Inner' "$F1")"
seed_work "$WID" "$FI" '1. Inside' 'An inner document.'
FE="$(seed_folder "$WID" 'Nothing here')"
get /stacks
assert_contains "2 readable folders" "list: two folders have documents of their own"
assert_contains "id=\"stack-row-$F1\" class=\"cut-row\" style=\"padding-left:0.0rem\"" "list: a row per folder, with an id the morph can key on"
assert_contains "id=\"stack-row-$FI\" class=\"cut-row\" style=\"padding-left:1.4rem\"" "list: a subfolder is indented 1.4rem a level"
assert_contains "href=\"/stacks/$F1\" style=\"font-family:var(--mg-serif)\" class=\"text-[1.05rem] hover:text-[var(--mg-accent)]\">Phoenix 1.8</a>" "list: the name links to the folder"
assert_contains "2 documents" "list: the document count"
assert_contains "1 documents" "list: and no pluralisation logic"
assert_not_contains "stack-row-$FE" "list: a folder with no documents of its own is not listed"
assert_not_contains "mg-badge ink" "list: nothing is read, nothing is badged"
assert_not_contains "· 0 read" "list: and no zero counts"

# somebody else's folders are not in the list, and not reachable
new_visitor other
ensure_user "stacks-other$RANDOM@example.com" "$PASS"
get /stacks
assert_contains "0 readable folders" "list: another user sees none of them"
get "/stacks/$F1"
assert_redirect_to /stacks "folder: and cannot open one"
get "/stacks/$F1/1"
assert_redirect_to /stacks "step: nor a step of it"
get "/stacks/$F1/story"
assert_redirect_to /stacks "story: nor its telling"

# ============================ a folder not yet read ===========================
new_visitor writer
login "$WRITER" "$PASS"
get "/stacks/$F1"
assert_status 200 "folder: the page is served"
assert_contains "2 documents · 0 read · 0 summarised · 0 mapped · 0 related · 0 pitfalls · 0 dependencies" "folder: the counts"
assert_contains "Not read yet. Reading is one call per document, in order, because each one is told what the ones before it established." "folder: an unread folder says so"
assert_contains '<span class="n">1</span>1. A chapter' "folder: and lists the documents in order"
assert_contains '<span class="n">2</span>2. Another chapter' "folder: all of them"
assert_contains 'phx-click="read">Read forwards</button>' "folder: the first pass is offered"
assert_contains 'phx-click="read_each">Read each document</button>' "folder: so is the ordinary read of each"
assert_contains 'phx-click="summarise">Summarise each document</button>' "folder: and the summaries"
assert_not_contains 'phx-click="compose"' "folder: nothing to compose yet"
assert_not_contains 'phx-click="deepen"' "folder: nor to deepen"
assert_not_contains 'phx-click="relate"' "folder: nor to relate until two have been mapped"
assert_not_contains "data-poll" "folder: and an idle page does not poll"
assert_not_contains "disabled" "folder: no button is disabled"

# ============== stack_run_test: the page as a viewer of a pass (seeded) ========
FV="$(seed_folder "$WID" 'Phoenix Viewer')"
seed_work "$WID" "$FV" '1. A chapter' 'A chapter to be read forwards, one word at a time.'
seed_step "$FV" 1 'read a folder forwards'

# test "a page that arrives mid-read shows the read, not the button"
run_row "$FV" running 4/12 read
get "/stacks/$FV"
assert_contains "4 of 12" "run: a page that arrives mid-read shows how far it is"
assert_contains "you can close the page" "run: and that it can be closed"
assert_contains "each document waits on the one before it." "run: the read's own sentence"
assert_contains "disabled" "run: and the buttons are disabled"
assert_contains 'data-poll="2"' "run: and the page asks again every two seconds"
assert_contains 'class="st-progress" style="--done:33%"' "run: with the bar at a third"
assert_not_contains '<button class="mg-btn" phx-click="read">' "run: the read button is the disabled one, not the live one"

# test "a page that arrives mid-compose says which part it is on"
run_row "$FV" running 2/5 compose:writing
get "/stacks/$FV"
assert_contains "Composing — part 2 of 5" "run: a page that arrives mid-compose says which part it is on"
assert_contains "Composing runs on the server too." "run: and that this too runs on the server"
assert_not_contains "class=\"st-progress\"" "run: a composition has no bar"

# test "an open page follows a pass it did not start"
sq "DELETE FROM runs WHERE key = 'stack:$FV'"
get "/stacks/$FV"
assert_not_contains "Composing" "run: an open page with no pass says nothing of one"
run_row "$FV" running 0/0 compose:outlining
poll "/stacks/$FV"
assert_contains "Composing — outlining" "run: the same page, polled, follows a pass something else started"
assert_contains 'data-poll=\"2\"' "run: and keeps polling"
run_row "$FV" done 0/0 'compose|ok'
poll "/stacks/$FV"
assert_not_contains "Composing —" "run: and lets go when it ends"
assert_not_contains "data-poll" "run: with nothing left to wait for"

# test "pressing the button twice does not start a second pass"
run_row "$FV" running 1/4 read
get "/stacks/$FV"
ev compose '{}' "/stacks/$FV"
assert_contains "A read pass is already running on this folder." "run: a second button while one runs is refused, by name"
assert_eq "$(sq "SELECT progress || ' ' || detail FROM runs WHERE key = 'stack:$FV'")" "1/4 read" "run: and the running pass is untouched"

# test "it will not start while another pass is running"
ev summarise '{}' "/stacks/$FV"
assert_contains "A read pass is already running on this folder." "run: summarise is refused the same way"
ev read '{}' "/stacks/$FV"
assert_contains "A read pass is already running on this folder." "run: so is the pass already running"
assert_eq "$(sq "SELECT count(*) FROM runs WHERE key = 'stack:$FV' AND status = 'running'")" "1" "run: still one"

# test "the summarise pass has its own button and its own sentence"
sq "DELETE FROM runs WHERE key = 'stack:$FV'"
get "/stacks/$FV"
assert_contains "Summarise each document" "run: the summarise pass has its own button"
assert_contains "0 summarised" "run: and its own count"
run_row "$FV" running 1/3 summarise
get "/stacks/$FV"
assert_contains "1 of 3" "run: a summarise tick shows its count"
assert_contains "one whole-document summary each" "run: and its own sentence"
assert_not_contains "waits on the one before it" "run: not the forward read's, which is not true of summaries"

# test "relating is a pass like the others, with its own sentence"
sq "DELETE FROM runs WHERE key = 'stack:$FV'"
get "/stacks/$FV"
assert_not_contains "Relate the documents" "run: one document is not a pair"
seed_work "$WID" "$FV" '2. Another' 'A second chapter, so there is something to relate the first to.'
get "/stacks/$FV"
assert_contains "Read each document" "run: relating needs each document's own map, which the forward read does not build"
assert_not_contains "Relate the documents" "run: and so is not offered yet"
sq "UPDATE works SET status = 'read' WHERE folder_id = $FV"
get "/stacks/$FV"
assert_contains "Relate the documents" "run: once both have been read, relating is offered"
assert_contains "0 related" "run: with its own count"
run_row "$FV" running 2/5 relate:relating
get "/stacks/$FV"
assert_contains "2 of 5" "run: a relate tick shows its count"
assert_contains "one call per pair" "run: and its own sentence"
assert_not_contains "waits on the one before it" "run: not the read's"
run_row "$FV" done 5/5 'relate|related:5:0'
poll "/stacks/$FV"
assert_contains "Related 5 pairs." "run: and when it ends, how many pairs"
poll "/stacks/$FV"
assert_not_contains "Related 5 pairs." "run: once"

# test "a pass that crashes frees the folder and says so"
run_row "$FV" running 0/0 compose
poll "/stacks/$FV"
assert_contains 'data-poll=\"2\"' "crash: the page is waiting on a pass"
run_row "$FV" crashed 0/0 'compose|crashed'
poll "/stacks/$FV"
assert_contains "The compose pass crashed. What finished is saved." "crash: the page says it crashed"
assert_not_contains "data-poll" "crash: and the folder is free"
get "/stacks/$FV"
assert_contains 'phx-click="read">Read forwards again</button>' "crash: its button is live again"

# test "a progress tick shows the work, not only the count"
FT="$(seed_folder "$WID" 'Phoenix Ticks')"
seed_work "$WID" "$FT" '1. First' 'The first of two documents being read.'
seed_work "$WID" "$FT" '2. Second' 'The second of two documents being read.'
seed_step "$FT" 1 'the first capability'
run_row "$FT" running 1/2 read
poll "/stacks/$FT"
assert_contains "the first capability" "tick: the step already written is on the page"
assert_not_contains "the second capability" "tick: and the one not yet written is not"
seed_step "$FT" 2 'the second capability'
run_row "$FT" running 2/2 read
poll "/stacks/$FT"
assert_contains "2 of 2" "tick: the next tick shows the count"
assert_contains "the second capability" "tick: and the step it just wrote, a forward read takes hours and the work must show"

# a job that died is given up on
run_row "$FT" running 1/2 read
sq "UPDATE runs SET pid = 2147483646 WHERE key = 'stack:$FT'"
get "/stacks/$FT"
assert_not_contains 'data-poll="2"' "dead: a run whose process is gone is not waited for"
assert_eq "$(sq "SELECT status FROM runs WHERE key = 'stack:$FT'")" "crashed" "dead: and is marked crashed"

# ============== the passes, for real, against fake_llm =========================
# --- the page is a viewer: a pass outlives the request that started it ----------
FS="$(seed_folder "$WID" 'Phoenix Slow')"
seed_work "$WID" "$FS" '1. Slow one' 'FAKE_LLM_SLOW the first of two documents, which answers late.'
seed_work "$WID" "$FS" '2. Slow two' 'FAKE_LLM_SLOW the second of two documents, which answers late.'
: > "$ACC"
get "/stacks/$FS"
keep
ev read '{}' "/stacks/$FS"
keep
assert_contains '"regions"' "slow: the button answers with the page"
assert_contains "of 2" "slow: and the page already shows the pass"
assert_contains "disabled" "slow: with its buttons disabled"
assert_eq "$(sq "SELECT status FROM runs WHERE key = 'stack:$FS'")" "running" "slow: the run is a row, and it is running"
get "/stacks/$FS"
assert_contains "you can close the page" "slow: a new page request finds the pass still going"
assert_contains 'data-poll="2"' "slow: and polls it"
ev compose '{}' "/stacks/$FS"
assert_contains "A read pass is already running on this folder." "slow: pressing another button during a real pass is refused by name"
wait_sql "SELECT status FROM runs WHERE key = 'stack:$FS'" done 40 "slow: the pass finishes though no page was holding it"
assert_eq "$(sq "SELECT detail FROM runs WHERE key = 'stack:$FS'")" "read|errors:2" "slow: both answers were late and unusable, so both documents failed, counted"
poll "/stacks/$FS"
keep
assert_seen "2 document(s) did not read." "slow: and the page says how many did not read"
poll "/stacks/$FS"
assert_not_contains 'data-poll' "slow: and stops polling"

# --- the forward read -----------------------------------------------------------
FP="$(seed_folder "$WID" 'Phoenix Passes')"
seed_work "$WID" "$FP" '1. The window' 'The first document says to start at a window and wait there a while.'
seed_work "$WID" "$FP" '2. The door' 'The second document builds a door in the wall beside the window.'
: > "$ACC"
get "/stacks/$FP"
ev read '{}' "/stacks/$FP"
keep
wait_sql "SELECT status || ' ' || detail FROM runs WHERE key = 'stack:$FP'" 'done read|errors:0' 40 "read: the forward read finishes with no document failed"
assert_eq "$(sq "SELECT count(*) FROM stack_steps WHERE folder_id = $FP")" "2" "read: one step per document"
assert_eq "$(sq "SELECT group_concat(ordinal) FROM (SELECT ordinal FROM stack_steps WHERE folder_id = $FP ORDER BY ordinal)")" "1,2" "read: in order"
poll "/stacks/$FP"
keep
assert_not_contains "of 2" "read: nothing is running"
get "/stacks/$FP"
assert_contains "2 documents · 2 read" "read: the page counts the steps"
assert_contains '<h2 class="cut-h">The method</h2>' "read: the chain is shown"
assert_contains '<span class="c">Watch from the window first</span>' "read: with the capability the model reported"
assert_contains "phx-click=\"read\">Read forwards again</button>" "read: the button now offers to read again"
assert_contains 'phx-click="deepen">Second pass</button>' "read: and the second pass"
assert_contains 'phx-click="compose">Compose the telling</button>' "read: and the composition"
assert_contains "href=\"/stacks/$FP/1\"" "read: each step has a page"
assert_llm_log_contains "POST /chat/completions -> You read one document out of an ordered series.report_step.json 200" "read: the model was asked once per document with the forward-read prompt"

# --- a step ---------------------------------------------------------------------
get "/stacks/$FP/1"
assert_status 200 "step: the step page is served"
assert_contains 'Step 1 of 2' "step: it knows where it is"
assert_contains '<h1 style="font-family:var(--mg-serif)">Watch from the window first</h1>' "step: the capability is the title"
assert_contains '<h2 class="cut-h">What to do</h2>' "step: what to do"
assert_contains 'Stand at the window and wait before anything else is built.' "step: the lesson"
assert_contains "from <a href=\"/works/stacks-" "step: it links to the document it came from"
assert_contains ">1. The window</a>" "step: by title"
assert_contains "href=\"/stacks/$FP\">← Phoenix Passes</a>" "step: and back to the folder"
assert_contains "Watch from the window first →" "step: forward to the next"
get "/stacks/$FP/9"
assert_status 200 "step: a step that is not there is still a page"
assert_contains "No step 9 here." "step: that says so"
get "/stacks/$FP/abc"
assert_status 500 "step: a segment that is not a number is a 500, as String.to_integer made it"

# --- the other passes, against a model with nothing to say ------------------------
# default.json has no tool call in it, so every document fails: the point is the pass, the run,
# the counts and the words. Each runs the real job body under a real fork.
: > "$ACC"
get "/stacks/$FP"
ev summarise '{}' "/stacks/$FP"
keep
wait_sql "SELECT status || ' ' || detail FROM runs WHERE key = 'stack:$FP'" 'done summarise|errors:2' 40 "summarise: the pass runs over every document and counts the ones that failed"
poll "/stacks/$FP"
keep
assert_seen "2 document(s) did not read." "summarise: and says so"

: > "$ACC"
get "/stacks/$FP"
ev read_each '{}' "/stacks/$FP"
keep
wait_sql "SELECT status FROM runs WHERE key = 'stack:$FP'" done 60 "read_each: the ordinary read of each document finishes"
assert_eq "$(sq "SELECT substr(detail, 1, 17) FROM runs WHERE key = 'stack:$FP'")" "read_each|errors:" "read_each: and reports as the read_each pass"
assert_eq "$(sq "SELECT count(*) FROM works WHERE folder_id = $FP AND status = 'read'")" "2" "read_each: both documents have been through the read"

# relating: now that both have been read there is something to relate
: > "$ACC"
get "/stacks/$FP"
assert_contains 'phx-click="relate">Relate the documents</button>' "relate: offered once two documents are mapped"
ev relate '{}' "/stacks/$FP"
keep
wait_sql "SELECT status || ' ' || detail FROM runs WHERE key = 'stack:$FP'" 'done relate|related:1:0' 60 "relate: triage chose the one pair and it was related"
poll "/stacks/$FP"
keep
assert_seen "Related 1 pair." "relate: and the page says Related 1 pair."
assert_eq "$(sq "SELECT count(*) > 0 FROM links WHERE a_work_id IN (SELECT id FROM works WHERE folder_id = $FP)")" "1" "relate: a link was made for the pair"

# --- compose, and the telling ------------------------------------------------------
: > "$ACC"
get "/stacks/$FP"
ev compose '{}' "/stacks/$FP"
keep
wait_sql "SELECT status || ' ' || detail FROM runs WHERE key = 'stack:$FP'" 'done compose|ok' 40 "compose: the composition finishes"
get "/stacks/$FP"
assert_contains '<div class="mg-label">The telling</div>' "compose: the folder page offers the telling"
assert_contains "href=\"/stacks/$FP/story\" class=\"t\">How the watching gets built</a>" "compose: titled by the model"
assert_contains "1 parts" "compose: and counts its parts"
assert_contains 'phx-click="compose">Compose again</button>' "compose: and offers to compose again"
assert_contains 'phx-click="publish"' "compose: private until published"
assert_contains "private — only you can read it" "compose: and says so"
get "/stacks/$FP/story"
assert_status 200 "story: the telling is a page"
assert_contains '<article class="st-story">' "story: it is one article"
assert_contains '<h1>How the watching gets built</h1>' "story: titled"
assert_contains '<h2><span class="n">1</span>The window</h2>' "story: a part is a numbered heading"
assert_contains 'Stand at the window first, and let the second document lean on the first.' "story: with its prose"
assert_contains '<aside class="st-turn md st-md"><p>Nobody notices the kettle.</p>' "story: and its turn"
assert_contains 'It begins at a window.' "story: the opening"
assert_contains 'That is the whole of it.' "story: the closing"
assert_contains "<a href=\"/stacks/$FP/1\" title=\"Watch from the window first\">1</a>" "story: each part names the steps it is from"
assert_contains 'phx-click="to-draft" class="mg-btn sm">Open as a draft</button>' "story: it can be opened as a draft"
assert_not_contains 'cut-stale' "story: nothing is stale or left out"
assert_llm_log_contains "-> Divide them into parts.outline_story.json 200" "compose: one call outlined it"
assert_llm_log_contains "-> You are writing one part of it.write_part.json 200" "compose: and one wrote the part"

# a step changed since the composition makes the telling stale
sq "UPDATE stack_steps SET lesson = 'Changed since.' WHERE folder_id = $FP AND ordinal = 1"
get "/stacks/$FP/story"
assert_contains 'The steps have been re-read since this was composed.' "story: a step changed since it was composed is called out"
get "/stacks/$FP"
assert_contains '<span class="cut-err">· stale</span>' "story: and so is the card on the folder page"

# test: open as a draft
ev to-draft '{}' "/stacks/$FP/story"
assert_contains '"redirect":"/works/' "draft: the telling opens as a draft, and the reader is taken to it"
assert_eq "$(sq "SELECT count(*) FROM works WHERE title = 'How the watching gets built' AND folder_id IS NULL AND user_id = $WID")" "1" "draft: a copy, not filed into the stack's own folder"
assert_eq "$(sq "SELECT count(*) FROM works WHERE folder_id = $FP")" "2" "draft: so the stack is still two documents"
get /stacks
assert_contains "Opened as a draft. Read it the way you would anything else." "draft: and the flash rides to the next page"

# no telling yet is a redirect with a flash
get "/stacks/$FV/story"
assert_redirect_to /stacks "story: a folder with no telling goes back to the list"
get /stacks
assert_contains "No telling for that folder yet." "story: with the reason"

# ================================ publishing ===================================
new_visitor writer
login "$WRITER" "$PASS"
get "/stacks/$FP"
ev publish '{}' "/stacks/$FP"
assert_contains "Only the account this deploy belongs to can publish." "publish: a writer who is not the owner of the deploy is refused"
assert_eq "$(sq "SELECT count(*) FROM folders WHERE published_at IS NOT NULL AND id = $FP")" "0" "publish: and the folder is not public"

new_visitor owner
ensure_user "$OWNER_MAIL" "$PASS"
OID="$(sq "SELECT id FROM users WHERE email = '$OWNER_MAIL'")"
FO="$(seed_folder "$OID" 'Owner Method')"
seed_work "$OID" "$FO" '1. Only' 'The only document of a method.'
seed_step "$FO" 1 'the only capability'
sq "INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, fingerprint) VALUES ($FO, 'The only telling', 'Open.', '[]', 'Close.', '[]', 'x');"
get "/stacks/$FO"
assert_contains 'data-confirm="Publish this stack? Anyone with the link will be able to read the telling and every step of it."' "publish: the button asks first"
ev publish '{}' "/stacks/$FO"
assert_contains "Published at /reading/owner-method" "publish: the owner publishes, and the slug is the name"
assert_contains "public at" "publish: the card says it is public"
assert_contains 'phx-click=\"unpublish\"' "publish: and offers to make it private"
assert_eq "$(sq "SELECT slug FROM folders WHERE id = $FO")" "owner-method" "publish: the slug is stored"
ev unpublish '{}' "/stacks/$FO"
assert_contains "Taken off the public site." "publish: and takes it down"
assert_eq "$(sq "SELECT published_at IS NULL FROM folders WHERE id = $FO")" "1" "publish: private again"
assert_eq "$(sq "SELECT slug FROM folders WHERE id = $FO")" "owner-method" "publish: the slug is kept, so publishing again restores the URL"
ev publish '{}' "/stacks/$FO"
assert_contains "Published at /reading/owner-method" "publish: and again, at the same address"

# ================================ /stacks/new ==================================
new_visitor writer
login "$WRITER" "$PASS"
get /stacks/new
ev form '{"repo":"phoenixframework/phoenix","token":"ghp_secret","folder":"","state":"all"}' /stacks/new
assert_contains 'value=\"phoenixframework/phoenix\"' "new: typing keeps the repository"
assert_contains 'placeholder=\"phoenixframework/phoenix\"' "new: and the folder placeholder follows it"
assert_not_contains "ghp_secret" "new: the token does not come back"
get /stacks/new
assert_contains 'value="phoenixframework/phoenix"' "new: and it is still there on the next request"
assert_not_contains "ghp_secret" "new: the token is not kept"
assert_eq "$(sq "SELECT count(*) FROM sessions WHERE data LIKE '%ghp_secret%'")" "0" "new: not in the session either"
ev import '{"repo":"justaname","token":"","folder":"","state":"open"}' /stacks/new
assert_contains "Write the repository as owner/name." "new: a repository that is not owner/name is told so"
assert_eq "$(sq "SELECT count(*) FROM runs WHERE key LIKE 'stack-import:%'")" "0" "new: and nothing was started"
ev form '{"repo":"a/b"}' /stacks/new
assert_not_contains "Write the repository as owner/name." "new: typing again clears the error"
get /stacks/new
assert_contains 'name="_csrf_token"' "new: the form carries the CSRF token"
assert_contains 'method="post"' "new: and posts, so a token is never put in an address"
