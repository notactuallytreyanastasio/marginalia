#!/usr/bin/env bash
# 25_import.sh: /import, the bulk import wizard (Source, Find, Choose, Import) and POST /import,
# the plain form that carries up to forty dropped files.
#
# Source tests (notes/tests.md part 6, import_flow_test, 25 tests) and the behaviours of
# notes/web-works-stacks.md section 3 (import_live).
#
# The Elixir test file drove the wizard with a FakeHub in place of GitHub. There is no fake
# GitHub in this harness and the importer's requests go to api.github.com, so:
#   * covered end to end here: the source step, the find step's refusals (the copy that is said
#     before any request is made), back and restart, the token never rendered, the dropped-files
#     path in full (curl multipart: folder naming, order, numbering, refusals, skips, the flash),
#     the CSRF and marker checks on POST /import;
#   * covered with the listing SEEDED: the choosing step (a row per pull request in the table
#     the page keeps, the wizard in the session row, both written with sqlite3), so the query
#     box, the regex box, the boxes, the order, the hint, the settings and the refusals of
#     "import" are the real server's;
#   * covered with the run SEEDED: the running step, its poll, a crash, the results step and the
#     redirect of a clean import are what the page does with a `runs` row; the job that writes
#     that row is the Temper tests' (pages_import_test, against importerFake);
#   * SKIPPED, named: finding against GitHub and importing from it (the SKIP lines below).
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

command -v sqlite3 >/dev/null 2>&1 || { skip "import: needs the sqlite3 command to seed the listing and the runs"; exit 0; }
command -v jq >/dev/null 2>&1 || { skip "import: needs jq to read the regions of an event's answer"; exit 0; }

sq() { sqlite3 -cmd '.timeout 5000' "$MARGINALIA_DB" "$@"; }

# ev_main NAME PAYLOAD: send an event for /import and put the inside of #main where the
# assertions look (BODY_F). An answer that is not a region (a redirect) is left as it is.
ev_main() {
  local payload="${2:-}"
  [ -z "$payload" ] && payload='{}'
  ev "$1" "$payload" /import
  if jq -e '.regions' "$BODY_F" >/dev/null 2>&1; then
    jq -r '.regions["#main"]' "$BODY_F" > "$T/main.html"
    cp "$T/main.html" "$BODY_F"
  fi
}

# poll_main: the refetch blimp.js makes while [data-poll] is on the page, as html
poll_main() {
  _curl GET /import -H 'x-requested-with: blimp' -H 'accept: application/json'
  if jq -e '.regions' "$BODY_F" >/dev/null 2>&1; then
    jq -r '.regions["#main"]' "$BODY_F" > "$T/main.html"
    cp "$T/main.html" "$BODY_F"
  fi
}

# A visitor with a session: the cookie id, the user, and the key of the session's rows.
begin_visitor() { # NAME
  new_visitor "$1"
  get /import
  SESSION="$(cookie_value _marginalia_key)"
  SID="$(printf '%s' "$SESSION" | shasum -a 256 | cut -c1-24)"
  UID_="$(sq "SELECT user_id FROM users_tokens WHERE id = (SELECT user_token_id FROM sessions WHERE id = '$SESSION')")"
}

# mkmd NAME TITLE: a markdown file in $T/files
mkdir -p "$T/files"
mkmd() { printf '# %s\n\n%s\n' "$2" "$(words 80)" > "$T/files/$1"; }

# post_files FOLDER NUMBER FILE...: POST /import as the dropped-files form sends it. A FILE is
# NAME or NAME:UPLOADNAME. The CSRF token is the one the last page showed.
post_files() {
  local folder="$1" number="$2"; shift 2
  local args=() f name up
  for f in "$@"; do
    name="${f%%:*}"; up="${f#*:}"
    args+=(-F "docs=@$T/files/$name;filename=$up")
  done
  _curl POST /import --form-string "_form=files" --form-string "folder=$folder" --form-string "number=$number" \
    ${CSRF:+--form-string "_csrf_token=$CSRF"} ${args[@]+"${args[@]}"}
}

WORKS_BEFORE="$(sq 'SELECT count(*) FROM works')"

# ============================ the first step ============================
# test "the first step is a choice of source, and creates nothing"
begin_visitor first
assert_status 200 "source: /import is open to anyone"
assert_contains "Import documents" "source: the page says Import documents"
assert_contains "Pull requests" "source: GitHub pull requests is a choice"
assert_contains "From this computer" "source: and so are files"
assert_contains 'phx-value-to="github"' "source: the card sends source/github"
assert_contains 'phx-value-to="files"' "source: the card sends source/files"
assert_contains '<li class="im-step on"><span>1</span> Source</li>' "source: the first of the four steps is lit"
assert_contains 'content="noindex, nofollow"' "source: the page asks not to be indexed"
assert_contains "Keep my drafts" "source: a stranger is given a guest of their own"
assert_not_contains "data-poll" "source: nothing is going on, so nothing polls"
assert_eq "$(sq 'SELECT count(*) FROM works')" "$WORKS_BEFORE" "source: nothing is created by looking"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "0" "source: the guest has no drafts"

# ============================ moving between steps ============================
# test "back walks the steps rather than reloading"
ev_main source '{"to":"github"}'
assert_contains 'id="im-find"' "find: source/github is the find step"
assert_contains '<li class="im-step on"><span>2</span> Find</li>' "find: the second step is lit"
assert_contains 'value="repo" checked' "find: One repository is the default"
assert_contains 'name="state"' "find: and asks which pull requests"
assert_contains 'type="password" name="token" value=""' "find: the token field is a password field with no value"
assert_contains "GitHub token" "find: and is labelled"
ev_main form '{"mode":"search","repo":"","query":"label:design","state":"all"}'
assert_contains 'name="query" value="label:design"' "find: the search mode swaps in its field"
assert_not_contains 'name="repo"' "find: and takes the repository field out"
assert_contains "<code>is:pr</code> is added for you" "find: and says what is done to the query"
ev_main back
assert_contains "Pull requests" "back: from the find step to the source step"
assert_not_contains "GitHub token" "back: and the find form is gone"
ev_main source '{"to":"files"}'
assert_contains "Drop up to 40 markdown or text files here" "files: the file step is reachable"
assert_contains 'id="im-files"' "files: it is its own form"
assert_contains 'enctype="multipart/form-data"' "files: which carries its files"
assert_contains 'action="/import"' "files: to POST /import"
assert_contains 'name="docs"' "files: in the docs field"
assert_contains 'multiple=""' "files: many at once"
assert_contains 'accept=".txt,.md,.markdown,.text"' "files: of the four extensions"
assert_contains 'name="_csrf_token"' "files: with the token the router checks"
assert_contains "left empty, named for what the files have in common" "files: the folder box says what it does when empty"
ev_main back
assert_contains "Pull requests" "back: from the files step to the source step"

# ============================ finding, refused before any request ============================
# test "a repository written wrongly is refused before any request"
ev_main source '{"to":"github"}'
ev_main find '{"mode":"repo","repo":"blimp","token":"t","state":"all"}'
assert_contains "Write the repository as owner/name." "find: a repository with no owner is refused in words"
assert_contains 'class="cut-err mt-4"' "find: in the sentence under the steps"
ev_main find '{"mode":"repo","repo":"temper/","token":"t","state":"all"}'
assert_contains "Write the repository as owner/name." "find: so is one with no name"
ev_main find '{"mode":"search","query":"   ","token":"","state":"all"}'
assert_contains "Write a search query first." "find: an empty search is refused"
ev_main find '{"mode":"repo","repo":"a b/c","token":"","state":"all"}'
assert_contains "Owner and repository must look like GitHub names." "find: names GitHub would not accept are explained"
assert_contains 'id="im-find"' "find: and the wizard stays on the find step"

# test "the token is never rendered back into the page"
ev_main find '{"mode":"repo","repo":"blimp","token":"ghp_secret_do_not_print","state":"all"}'
assert_not_contains "ghp_secret_do_not_print" "token: not in the answer to the find that was given it"
get /import
assert_not_contains "ghp_secret_do_not_print" "token: nor on the next page"

# test "restart" (the results step's way back is exercised below; here the source step's own)
ev_main restart
assert_contains "Pull requests" "restart: back to the source step"

# ============================ the choosing step, listing seeded ============================
seed_listing() {
  begin_visitor "$1"
  ev_main source '{"to":"github"}'
  local wiz='{"step":"pick","source":"github","repo":"temper/blimp","query":"","mode":"repo","state":"all","pattern":"","how":"query","order":"oldest","folder":"temper/blimp","commits":"1","files":"1","number":"0","patternError":"","hintWas":"","hintTry":"","error":""}'
  local path='$.ui."import:wiz"'
  sq "DELETE FROM import_pulls WHERE sid = '$SID';
      INSERT INTO import_pulls (sid, pos, repo, number, title, url, state, draft, base, head, updated_at, created_at, merged_at, shown, chosen) VALUES
       ('$SID', 0, 'temper/blimp', 8, 'Revert the fix', 'https://example.invalid/pull/8', 'open', 0, 'main', 'b8', '2026-01-01T00:00:00Z', '2025-01-01T00:00:00Z', NULL, 1, 1),
       ('$SID', 1, 'temper/blimp', 7, 'Add a test', 'https://example.invalid/pull/7', 'merged', 1, 'main', 'b7', '2026-01-01T00:00:00Z', '2025-01-01T00:00:00Z', '2025-02-01T00:00:00Z', 1, 1),
       ('$SID', 2, 'temper/blimp', 6, 'Nothing to do with it', 'https://example.invalid/pull/6', 'open', 0, 'main', 'b6', '2026-01-01T00:00:00Z', '2025-03-01T00:00:00Z', NULL, 1, 1),
       ('$SID', 3, 'temper/blimp', 9, 'Fix the parser', 'https://example.invalid/pull/9', 'merged', 0, 'main', 'b9', '2026-01-01T00:00:00Z', '2025-01-01T00:00:00Z', '2025-04-01T00:00:00Z', 1, 1);
      UPDATE sessions SET data = json_set(data, '$path', '$wiz') WHERE id = '$SESSION';"
}

# row_order: the numbers on the rows of the list, in the order they stand
row_order() { grep -o 'phx-value-key="temper/blimp#[0-9]*"' "$BODY_F" | sed 's/.*#\([0-9]*\)"/\1/' | tr '\n' ',' | sed 's/,$//'; }

# test "finding lists the pull requests without importing any" / "the list is oldest first"
seed_listing lister
poll_main
assert_contains "Fix the parser" "pick: the pull requests are listed"
assert_contains "Revert the fix" "pick: all of them"
assert_contains "<b>4 selected</b>" "pick: all four are ticked"
assert_contains '<li class="im-step on"><span>3</span> Choose</li>' "pick: the third step is lit"
assert_eq "$(row_order)" "8,7,6,9" "pick: oldest first, by when it landed, so the folder reads forwards"
assert_contains 'id="im-row-temper-blimp-9"' "pick: a row has a stable id"
assert_contains 'class="s merged">merged' "pick: a merged one says so"
assert_contains '<span class="d">2025-04-01</span>' "pick: with the day it landed"
assert_contains '<span class="s draft">draft</span>' "pick: a draft says so"
assert_contains 'name="folder" value="temper/blimp"' "pick: the folder box starts as the repository"
assert_eq "$(sq 'SELECT count(*) FROM works')" "$WORKS_BEFORE" "pick: a listing is not an import"

# test "a title regex filters the list and sets the selection"
ev_main pattern '{"how":"regex","pattern":"fix"}'
assert_contains "Fix the parser" "regex: a match is kept"
assert_contains "Revert the fix" "regex: and is case insensitive"
assert_not_contains "Nothing to do with it" "regex: what does not match is gone"
assert_contains "<b>2 selected</b>" "regex: and what is left is ticked"
assert_contains "2 pull requests shown of 4" "regex: the bar says how many of how many"

# test "a pattern that will not compile says so and keeps the list"
ev_main pattern '{"how":"regex","pattern":"(unclosed"}'
assert_contains "Fix the parser" "regex: a half-typed pattern does not empty the page"
assert_contains 'class="cut-err mt-2"' "regex: the error is under the box"

# test "the boxes have the last word over the regex"
ev_main pattern '{"how":"regex","pattern":"fix"}'
ev_main toggle '{"key":"temper/blimp#6"}'
assert_contains "<b>3 selected</b>" "boxes: ticking one the pattern hid selects it"
ev_main toggle '{"key":"temper/blimp#6"}'
assert_contains "<b>2 selected</b>" "boxes: and ticking it again takes it back"

# test "clearing and selecting work on what is shown, not on everything"
ev_main none
assert_contains "<b>0 selected</b>" "boxes: clear shown clears what is shown"
assert_contains 'type="submit" disabled>Import 0' "boxes: and the Import button is disabled"
ev_main all
assert_contains "<b>2 selected</b>" "boxes: select all shown selects what is shown, not the two the pattern hid"

# the query box
ev_main pattern '{"how":"query","pattern":"state:open"}'
assert_contains "Revert the fix" "query: state:open keeps an open one"
assert_contains "Nothing to do with it" "query: and the other"
assert_not_contains "Fix the parser" "query: and drops a merged one"
assert_contains "<b>2 selected</b>" "query: and ticks what is left"
ev_main pattern '{"how":"query","pattern":"is:pr state:merged"}'
assert_contains "Fix the parser" "query: the shape from the report"
assert_contains "<b>2 selected</b>" "query: is:pr is a no-op and merged is two"
ev_main pattern '{"how":"query","pattern":"fix"}'
assert_contains "<b>2 selected</b>" "query: a bare word matches the title"
ev_main pattern '{"how":"query","pattern":"-fix"}'
assert_contains "<b>2 selected</b>" "query: and a minus takes it away"
ev_main pattern '{"how":"query","pattern":"stat:closed"}'
assert_contains "do not know" "query: a typo is refused by name"
assert_contains "stat" "query: and the word is named"
assert_contains "Add a test" "query: the list stays while the query is wrong"
assert_contains "<b>2 selected</b>" "query: and so does the selection"
ev_main pattern '{"how":"regex","pattern":"fix|test"}'
assert_contains "<b>3 selected</b>" "language: a regex alternation matches three"
ev_main pattern '{"how":"query","pattern":"fix|test"}'
assert_contains "<b>0 selected</b>" "language: the same text in the query language is one word"

# test "an empty query explains itself when it is the guessable mistake"
ev_main pattern '{"how":"query","pattern":"created:@today-90d"}'
assert_contains "Nothing matches that query" "hint: an empty result says so"
assert_contains "that one day" "hint: and says what the query meant"
assert_matches 'created:(&gt;|>)@today-90d' "hint: and what to write instead"
# test "and says nothing when the query is simply too narrow"
ev_main pattern '{"how":"query","pattern":"nonesuch"}'
assert_contains "Nothing matches that query" "hint: too narrow is just empty"
assert_not_contains "that one day" "hint: with no hint"

# test "re-applies the filter instead of reloading the page" (Enter sends the same event)
ev_main pattern '{"how":"query","pattern":"state:merged"}'
assert_contains "Fix the parser" "enter: the same event, the same list"
assert_contains '<li class="im-step on"><span>3</span> Choose</li>' "enter: still on the choosing step"
assert_not_contains 'phx-value-to="github"' "enter: not back at the source step"

# order
ev_main pattern '{"how":"query","pattern":""}'
ev_main order '{"order":"newest"}'
assert_eq "$(row_order)" "9,6,7,8" "order: newest first is the reverse"
assert_contains "<b>4 selected</b>" "order: and the selection starts over"
ev_main order '{"order":"oldest"}'
assert_eq "$(row_order)" "8,7,6,9" "order: and back"

# settings
ev_main settings '{"folder":"Picked","commits":"false","files":"true","number":"true"}'
assert_contains 'name="folder" value="Picked"' "settings: the folder box keeps what was typed"
assert_contains 'name="number" value="true" checked' "settings: a ticked box stays ticked"
assert_contains '<b>Include the commit trail.</b>' "settings: the commit trail is a choice"
assert_not_contains 'name="commits" value="true" checked' "settings: and is off when it said false"

# import, refused before any request
ev_main none
ev_main import '{}'
assert_contains "Nothing is selected." "import: nothing selected is refused in words"
assert_eq "$(sq 'SELECT count(*) FROM works')" "$WORKS_BEFORE" "import: and nothing is created"

# test "the token is never rendered back into the page" (the choosing step and the settings)
assert_not_contains "ghp_" "token: no token anywhere on the choosing step"

# back from the choosing step keeps the listing for the way forward
ev_main back
assert_contains "GitHub token" "back: from the listing to the find form"
ev_main back
assert_contains "Pull requests" "back: and from there to the source step"

skip "find and import against api.github.com: there is no fake GitHub in this harness (pages_import_test drives importerListPulls, importerSearch and importerDocuments against importerFake)"
skip "a search lists across repositories, and GitHub's refusal is reported in words (needs the search API)"
skip "importing lands them in a folder and says what could not be fetched (needs the pull request API; the results page is checked below from a seeded run)"

# ============================ watching an import, run seeded ============================
begin_visitor runner
ev_main source '{"to":"github"}'
WIZ_RUNNING='{"step":"running","source":"github","repo":"temper/blimp","query":"","mode":"repo","state":"all","pattern":"","how":"query","order":"oldest","folder":"Later","commits":"1","files":"1","number":"0","patternError":"","hintWas":"","hintTry":"","error":""}'
set_wiz() { sq "UPDATE sessions SET data = json_set(data, '\$.ui.\"import:wiz\"', '$1') WHERE id = '$SESSION';"; }
set_wiz "$WIZ_RUNNING"
RUNKEY="import:$SID"
sq "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ('$RUNKEY', 'running', '3/10', 'fetching', NULL, datetime('now'), NULL);"
get /import
assert_status 200 "running: /import while an import is going"
assert_contains "Reading them off GitHub" "running: says what it is doing"
assert_contains "3 of 10" "running: and how far it has got"
assert_contains 'style="width:30%"' "running: the bar is at 30%"
assert_contains 'data-poll="2"' "running: and asks to be fetched again in two seconds"
assert_contains '<li class="im-step on"><span>4</span> Import</li>' "running: the fourth step is lit"
assert_not_contains 'phx-value-to="github"' "running: a page load does not start the wizard over"
sq "UPDATE runs SET progress = '1/3', detail = 'landing' WHERE key = '$RUNKEY';"
poll_main
assert_contains "Filing them" "running: the poll shows the second half"
assert_contains 'style="width:33%"' "running: with its own bar"
assert_contains 'data-poll="2"' "running: and keeps polling"

# a run that crashed
sq "UPDATE runs SET status = 'crashed', detail = 'Bubble: disk full', finished_at = datetime('now') WHERE key = '$RUNKEY';"
poll_main
assert_contains "The import crashed: Bubble: disk full" "crash: the poll that finds it says so"
assert_contains "start again" "crash: and offers to start again"
assert_not_contains "data-poll" "crash: and stops polling"
ev_main restart
assert_contains "Pull requests" "restart: from the results step back to the source step"

# a run that finished with something not fetched: the results step
FOLDER_ID="$(sq "INSERT INTO folders (name, user_id) VALUES ('Later', $UID_); SELECT last_insert_rowid();")"
set_wiz "$WIZ_RUNNING"
RESULT='{"folder":"'"$FOLDER_ID"'","created":"3","skipped":["Old one"],"failed":[["Empty one","there is no text in it"]],"missed":[["7","Add a test","No such repository, or the token cannot see it."]]}'
sq "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ('$RUNKEY', 'done', '3/3', '$RESULT', NULL, datetime('now'), datetime('now'));"
poll_main
assert_contains "3 drafts imported." "results: how many were filed"
assert_contains "1 was already in the folder under the same title and was left alone." "results: how many were skipped"
assert_contains "Not imported" "results: what failed to land"
assert_contains "Empty one — there is no text in it" "results: and why"
assert_contains "Could not be fetched" "results: what could not be fetched"
assert_contains "#7 Add a test — No such repository, or the token cannot see it." "results: named, with the reason"
assert_contains "href=\"/stacks/$FOLDER_ID\"" "results: a link to the folder"
assert_contains "Open the folder" "results: that says so"
assert_not_contains "data-poll" "results: nothing left to poll for"

# a run that finished clean: on to the folder, with the flash
ev_main restart
set_wiz "$WIZ_RUNNING"
CLEAN='{"folder":"'"$FOLDER_ID"'","created":"3","skipped":[],"failed":[],"missed":[]}'
sq "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ('$RUNKEY', 'done', '3/3', '$CLEAN', NULL, datetime('now'), datetime('now'));"
_curl GET /import -H 'x-requested-with: blimp' -H 'accept: application/json'
assert_json_path .redirect "/stacks/$FOLDER_ID" "clean: the poll answers with a redirect to the folder"
get "/stacks/$FOLDER_ID"
assert_contains "3 drafts imported." "clean: and the folder's page carries the flash"
get /import
assert_contains "Pull requests" "clean: the wizard is over; the next visit starts at the source step"

# ============================ files dropped on the page ============================
# test "the file step is reachable and starts empty" / the path end to end
begin_visitor dropper
ev_main source '{"to":"files"}'
mkmd chapter-03.md "Three"
mkmd chapter-01.md "One"
mkmd chapter-02.md "Two"
post_files "" false chapter-03.md chapter-01.md chapter-02.md
assert_status 303 "files: a clean drop is a redirect"
FID="$(sq "SELECT id FROM folders WHERE user_id = $UID_ AND name = 'chapter'")"
assert_eq "$(printf '%s' "$FID" | grep -c '^[0-9][0-9]*$')" "1" "files: a folder named for what the files share (chapter)"
assert_redirect_to "/stacks/$FID" "files: to that folder"
assert_eq "$(sq "SELECT group_concat(title, '|') FROM (SELECT title FROM works WHERE folder_id = $FID ORDER BY title)")" "chapter-01|chapter-02|chapter-03" "files: a draft per file, named after it"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_ AND folder_id IS NULL")" "0" "files: none of them loose"
get "/stacks/$FID"
assert_status 200 "files: the folder's page opens"
assert_contains "3 drafts imported." "files: and carries the flash"
assert_contains "chapter" "files: and the folder's name"

# the guest's session is the owner
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "3" "files: the drafts are the guest's own"

# natural order, and numbering follows it
begin_visitor orderer
mkmd chapter-2.md "Two"
mkmd chapter-10.md "Ten"
post_files "" true chapter-10.md chapter-2.md
assert_status 303 "order: numbered files redirect"
assert_eq "$(sq "SELECT group_concat(title, '|') FROM (SELECT title FROM works WHERE user_id = $UID_ ORDER BY title)")" "1. chapter-2|2. chapter-10" "order: chapter-2 before chapter-10, and numbered in that order"

# the folder box wins
begin_visitor namer
post_files "  My book  " false chapter-01.md chapter-02.md
assert_status 303 "folder: a named drop redirects"
assert_eq "$(sq "SELECT count(*) FROM folders WHERE user_id = $UID_ AND name = 'My book'")" "1" "folder: the box, trimmed, is the folder"

# one file
begin_visitor single
mkmd notes.md "Notes"
post_files "" false notes.md
assert_eq "$(sq "SELECT count(*) FROM folders WHERE user_id = $UID_ AND name = 'notes'")" "1" "folder: a single file is a folder named for it"

# files with nothing in common
begin_visitor strangers
mkmd apple.md "Apple"
mkmd zebra.md "Zebra"
post_files "" false apple.md zebra.md
assert_eq "$(sq "SELECT count(*) FROM folders WHERE user_id = $UID_ AND name LIKE 'Imported 20%'")" "1" "folder: files with nothing in common are filed under the moment"

# a file that is not text or markdown is named beside the one that went in
begin_visitor mixed
printf '%%PDF-1.4 binary' > "$T/files/scan.pdf"
post_files "Mixed" false chapter-01.md scan.pdf
assert_status 200 "refused: a drop with a bad file shows the results"
assert_contains "1 draft imported." "refused: the good one went in"
assert_contains "Not imported" "refused: the other is listed"
assert_contains "scan.pdf — not a text or markdown file" "refused: with the reason"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "1" "refused: only the good one was filed"

# an empty file fails alone
begin_visitor emptied
: > "$T/files/empty.md"
post_files "Two" false chapter-01.md empty.md
assert_status 200 "empty: a drop with an empty file shows the results"
assert_contains "empty — there is no text in it" "empty: named, with the reason"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "1" "empty: the other was filed"

# a second drop of the same files skips them
begin_visitor again
post_files "Twice" false chapter-01.md chapter-02.md
assert_status 303 "again: the first drop redirects"
post_files "Twice" false chapter-01.md chapter-02.md
assert_status 303 "again: so does the second"
get_follow "$LOCATION"
assert_contains "0 drafts imported, 2 already there and left alone." "again: the second skips both and says so"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "2" "again: no duplicates"

# nothing chosen
begin_visitor nothing
ev_main source '{"to":"files"}'
get /import
post_files "" false
assert_status 422 "none: a drop of no files is refused"
assert_contains "No files yet — drop some in." "none: in words"
assert_contains 'id="im-files"' "none: and the step stays"

# more than forty
begin_visitor toomany
get /import
many=()
n=1
while [ "$n" -le 41 ]; do
  mkmd "many-$n.md" "Many $n"
  many+=("many-$n.md")
  n=$((n + 1))
done
post_files "" false "${many[@]}"
assert_status 422 "forty: forty-one files are refused"
assert_contains "more than 40 files" "forty: in words"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = $UID_")" "0" "forty: and none is filed"

# the form's marker and the token
begin_visitor marker
get /import
_curl POST /import --form-string "repo=temper/blimp" --form-string "token=ghp_x" ${CSRF:+--form-string "_csrf_token=$CSRF"}
assert_status 303 "marker: a post that is not the files form is turned back"
assert_redirect_to /import "marker: to the wizard, not to a page with the token in its address"
begin_visitor nocsrf
get /import
CSRF_SAVED="$CSRF"; CSRF=""
_curl POST /import --form-string "_form=files" --form-string "folder=" -F "docs=@$T/files/chapter-01.md;filename=chapter-01.md"
assert_status 403 "csrf: a files post without the token is refused"
CSRF="$CSRF_SAVED"
assert_eq "$(sq "SELECT count(*) FROM works WHERE user_id = (SELECT user_id FROM users_tokens WHERE id = (SELECT user_token_id FROM sessions WHERE id = '$(cookie_value _marginalia_key)'))")" "0" "csrf: and nothing was filed"
