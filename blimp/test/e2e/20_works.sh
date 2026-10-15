#!/usr/bin/env bash
# 20_works.sh: guests, the draft list and its folder tree, uploading a draft (form, file, plain POST).
#
# Source tests (notes/tests.md parts 9 and 8): guest_upload_test (13), work_upload_fallback_test (8),
# work_tree_test (15). Also here: the file upload and the fetch box, which the Elixir tested only
# through LiveView, and the tree's events.
#
# Pages this file does not own: /works/:slug (the show page) and /works/:slug/graph.json belong to
# another group. Every assertion that needs them runs only once GET /works/<slug> answers with the
# draft (show_ready), and is a SKIP before that.
#
# Event names (ev ...) are the Elixir handler names: new_folder, backfill, toggle, rename_start,
# rename_cancel, rename, delete_folder, move, delete on /works; fetch, validate, save on /works/new.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

D="$E2E_DIR/fixtures/drafts"
PASS='hello world!'
BODY300="$(words 300)"

# show_ready SLUG TITLE: true when the show page is there and carries the draft's title.
show_ready() {
  get "/works/$1"
  [ "$STATUS" = 200 ] && grep -qF -- "$2" "$BODY_F"
}

# assert_located DESC: the last response redirects to /works/<something>.
assert_located() {
  case "$STATUS:$LOCATION" in
    30[0-9]:/works/?*|30[0-9]:http*/works/?*) _ok "$1 ($LOCATION)" ;;
    *) _bad "$1" "expected a redirect to /works/<slug>, got status $STATUS, Location: $LOCATION" ;;
  esac
}

# assert_num VALUE DESC: VALUE is a number (an id read off the page).
assert_num() {
  case "$1" in
    ''|*[!0-9]*) _bad "$2" "not a number: '$1'" ;;
    *) _ok "$2 ($1)" ;;
  esac
}

# folder_id NAME / work_id TITLE: the id, read off the last /works page (HTML, not an event reply).
folder_id() { sed -n "s/.*class=\"mg-fname\" phx-click=\"toggle\" phx-value-id=\"\([0-9]*\)\">$1<.*/\1/p" "$BODY_F" | head -1; }
work_id() { sed -n "s/.*data-drag-kind=\"work\" data-drag-id=\"\([0-9]*\)\" style=\"[^\"]*\"><span class=\"mg-grip\"[^>]*>[^<]*<\/span><div class=\"min-w-0 flex-1\"><a href=\"[^\"]*\"[^>]*>$1<.*/\1/p" "$BODY_F" | head -1; }

# upload_file PATH FILENAME [TITLE]: multipart POST /works/new with the file in the manuscript field.
upload_file() {
  get /works/new
  _curl POST /works/new -F "manuscript=@$1;filename=$2" --form-string "work[title]=${3:-}" \
    --form-string "work[intent]=" --form-string "work[body]=" ${CSRF:+--form-string "_csrf_token=$CSRF"}
}

# ============================== guest_upload_test ==============================
# describe "arriving with no account"
# test "is let in, and given a guest of their own"
new_visitor guest-a
get /works/new
assert_status 200 "guest: /works/new is open to anyone"
assert_contains "Upload a draft" "guest: the page says Upload a draft"
assert_cookie _marginalia_key "guest: a session token is created for the guest"
assert_contains "Keep my drafts" "guest: the nav marks them as a guest (Keep my drafts -> /users/register)"

# test "the same session keeps the same guest"
upload_text "Mine" "$BODY300"
SLUG="$(draft_slug)"
assert_redirect_to "/works/$SLUG" "guest: uploading redirects to /works/<slug>"
get /works
assert_contains "Mine" "guest: the same session sees its own draft again (same guest)"

# test "two different visitors get two different guests"
new_visitor guest-b
get /works/new
assert_cookie _marginalia_key "guest: a second visitor gets a session of their own"
get /works
assert_not_contains "Mine" "guest: and a different guest, with no drafts of the first"

# describe "a draft is unlisted, and the link is the permission"
# test "the url carries an unguessable slug, not the row id"
assert_eq "$([ "${#SLUG}" -ge 20 ] && echo long)" "long" "guest: the slug is at least 20 characters ($SLUG)"
assert_eq "$([ "$SLUG" != "1" ] && echo different)" "different" "guest: the slug is not the row id"

# test "a guessed slug gets nothing"  (the show page's rule)
new_visitor guest-a
if show_ready "$SLUG" "Mine"; then
  get /works/1
  assert_redirect_to "/works" "guest: /works/1 goes back to /works"
  get /works/1/graph.json
  assert_status 404 "guest: /works/1/graph.json is a 404"

  # test "the owner sees it as theirs, with a link to hand out"
  get "/works/$SLUG"
  assert_contains "Mine" "guest owner: sees the title"
  assert_contains "Copy link" "guest owner: has a Copy link"
  assert_not_contains "reading someone&#39;s draft" "guest owner: no 'reading someone's draft' banner"

  # test "someone with the link can read it"
  new_visitor guest-c
  get "/works/$SLUG"
  assert_status 200 "guest reader: the link opens the draft"
  assert_contains "Mine" "guest reader: sees the title"
  assert_contains "reading someone&#39;s draft" "guest reader: sees the 'reading someone's draft' banner"
  assert_not_contains "Copy link" "guest reader: has no Copy link"

  # test "but cannot spend the owner's model credit or change the draft"
  calls0="$(llm_calls)"
  ev send '{"message":"hello"}' "/works/$SLUG"
  assert_contains "You can read it, not change it" "guest reader: send says You can read it, not change it"
  ev build_graph '{}' "/works/$SLUG"
  assert_contains "You can read it, not change it" "guest reader: build_graph says You can read it, not change it"
  ev start_read '{}' "/works/$SLUG"
  assert_contains "You can read it, not change it" "guest reader: start_read says You can read it, not change it"
  assert_eq "$(llm_calls)" "$calls0" "guest reader: nothing was asked of the model"
  new_visitor guest-a
  get "/works/$SLUG"
  assert_not_contains 'data-poll' "guest owner: nothing was started (the page is not waiting on a read)"
else
  skip "guest: a guessed slug gets nothing (needs the /works/:slug page)"
  skip "guest owner: sees the title and a Copy link (needs the /works/:slug page)"
  skip "guest reader: opens the draft read-only (needs the /works/:slug page)"
  skip "guest reader: cannot spend the model credit or change the draft (needs the /works/:slug page)"
fi

# test "it does not show up in anyone else's list"
new_visitor guest-d
get /works
assert_not_contains "Mine" "guest: another visitor's /works does not list it"

# describe "settings still need a real account"
# test "a guest is sent to sign up, not to log in — they have nothing to log in with"
new_visitor guest-e
get /works/new
get /users/settings
assert_redirect_to "/users/register" "guest: /users/settings sends a guest to /users/register"
# test "a real account gets in"
new_visitor real-a
ensure_user "$(new_email)" "$PASS"
get /users/settings
assert_status 200 "real account: /users/settings opens"

# describe "claiming the account keeps the work"
# The Elixir page sent anyone holding a session, a guest included, from /users/register to /, and
# nothing called Accounts.claim_guest_account (it is tested at the context level). So over HTTP a
# guest cannot register; what can be checked is that, and that a real account keeps its drafts.
# test "a guest on the registration page is sent away"
new_visitor claim
upload_text "Kept" "$BODY300"
get /users/register
assert_redirect_to "/" "claim: a guest on /users/register is sent to /, as the LiveView did"
get /works
assert_contains "Kept" "claim: and the draft is still theirs"
skip "claim: a guest becomes a real user in place (Accounts.claim_guest_account has no caller; context-level only)"
# test "a real account keeps what it uploads"
new_visitor claim-login
CLAIMED="claimed$RANDOM@example.com"
ensure_user "$CLAIMED" "a-long-enough-password"
upload_text "Real" "$BODY300"
get /works
assert_contains "Real" "claim: a real account lists its draft"
assert_not_contains "Keep my drafts" "claim: and is not a guest"
# test "claiming a real account is refused"
get /users/register
assert_redirect_to "/" "claim: a real account on /users/register is sent away, not re-claimed"

# ========================= work_upload_fallback_test ==========================
# describe "the form the browser submits on its own"
# test "carries an action and a CSRF token"
new_visitor fallback
get /works/new
assert_matches '<form[^>]*action="/works/new"' "fallback: the form has action=/works/new (else the browser posts to whatever page it is on)"
assert_contains 'name="_csrf_token"' "fallback: the form carries a _csrf_token (the POST is rejected without it)"
assert_matches '<form[^>]*enctype="multipart/form-data"' "fallback: and is multipart, so a file can ride along"
assert_matches 'type="file"[^>]*name="manuscript"|name="manuscript"[^>]*type="file"' "fallback: the form has the file input"
assert_contains 'accept=".txt,.md,.markdown,.text"' "fallback: the file input accepts the four extensions"

# describe "POST /works/new"
# test "saves the draft and goes to it, rather than 404ing"
new_visitor fallback-user
ensure_user "$(new_email)" "$PASS"
upload_text "Pasted" "$(cat "$D/kettle.md")" ""
S="$(draft_slug)"
assert_redirect_to "/works/$S" "fallback: POST /works/new redirects to /works/<slug>"
if show_ready "$S" "Pasted"; then
  assert_status 200 "fallback: the page it sends them to is there"
  assert_contains "Pasted" "fallback: and it shows the title"
else
  get /works
  assert_contains "Pasted" "fallback: the draft is in /works (the /works/:slug page is not here yet)"
  skip "fallback: and the page it sends them to shows the title (needs the /works/:slug page)"
fi
# test "a visitor with no account at all gets one on the way in"
new_visitor fallback-anon
upload_text "Anon" "$(cat "$D/kettle.md")"
S2="$(draft_slug)"
assert_located "fallback: an anonymous POST redirects to a draft"
get /works
assert_contains "Anon" "fallback: the anonymous draft was saved under a guest"
# test "an untitled draft still saves"
new_visitor fallback-untitled
upload_text "   " "$(cat "$D/kettle.md")"
get /works
assert_contains "Untitled draft" "fallback: a blank title becomes Untitled draft"

# describe "when the plain POST cannot be saved"
# test "an empty draft says so"
new_visitor fallback-empty
upload_text "Nothing" "   "
assert_status 422 "fallback: an empty draft is a 422"
assert_contains "There&#39;s no text there yet" "fallback: says There's no text there yet"
assert_contains "paste a draft or attach a file." "fallback: and what to do (a file can be attached on this page)"
assert_not_contains "404" "fallback: and is not a 404 page"
assert_contains "Upload a draft" "fallback: it is the upload page again"
# test "the writer's text is still in the box"
LONG="$T/long.txt"; words 120001 > "$LONG"
new_visitor fallback-long
get /works/new
_curl POST /works/new --form-string "work[title]=Too big" -F "work[body]=<$LONG" --form-string "work[intent]=a test" ${CSRF:+--form-string "_csrf_token=$CSRF"}
assert_status 422 "fallback: 120,001 words is a 422"
assert_contains "and the limit is 120,000 for now" "fallback: says and the limit is 120,000 for now"
assert_contains 'value="Too big"' "fallback: the title is still in its box"
assert_contains "a test" "fallback: the intent is still in its box"
assert_contains "$(words 50)" "fallback: the writer's text is still in the box (50 words of it)"
# test "nothing is written when the draft is rejected"
new_visitor fallback-nothing
ensure_user "$(new_email)" "$PASS"
upload_text "Nope" ""
get /works
assert_not_contains "Nope" "fallback: a rejected draft is not in /works"

# describe "the two paths agree"
# test "the LiveView and the plain POST reject the same draft"
new_visitor fallback-agree
get /works/new
OVER="$T/over.json"; { printf '{"payload":{"work":{"title":"x","body":"'; cat "$LONG"; printf '"}},"path":"/works/new"}'; } > "$OVER"
_curl POST /ev/save -H 'x-requested-with: blimp' -H 'content-type: application/json' ${CSRF:+-H "x-csrf-token: $CSRF"} --data @"$OVER"
assert_contains "and the limit is 120,000 for now" "agree: the save event says and the limit is 120,000 for now"
# the same event, for a draft that is fine, navigates
GOOD="$(cat "$D/kettle.md" | jq -Rs . 2>/dev/null)"
if [ -n "$GOOD" ]; then
  ev save "{\"work\":{\"title\":\"By event\",\"body\":$GOOD}}" /works/new
  assert_contains '"redirect":"/works/' "agree: the save event of a good draft answers with a redirect to it"
else
  skip "agree: the save event of a good draft redirects (needs jq)"
fi

# ================================ the upload page ==============================
# describe "attaching a file"
new_visitor file-a
upload_file "$D/kettle.md" "kettle.md"
FS="$(draft_slug)"
assert_redirect_to "/works/$FS" "file: a .md file uploads and goes to the draft"
get /works
assert_contains ">kettle<" "file: the draft is titled by the file's name, less the extension"
upload_file "$D/lighthouse.txt" "Lighthouse.TXT" "A title I chose"
assert_located "file: a .TXT file is accepted in any case"
get /works
assert_contains "A title I chose" "file: a typed title wins over the file's name"
assert_not_contains ">Lighthouse<" "file: and the file's name is not used then"

# test "pasted text is ignored when there is a file"
get /works/new
_curl POST /works/new -F "manuscript=@$D/notes-on-a-server.md;filename=notes.md" --form-string "work[title]=Both" \
  --form-string "work[body]=pasted words that are not the draft" ${CSRF:+--form-string "_csrf_token=$CSRF"}
assert_located "file: file and pasted text together make a draft"
BOTH="$(draft_slug)"
if show_ready "$BOTH" "Both"; then
  assert_not_contains "pasted words that are not the draft" "file: and the draft is the file's text, not the pasted text"
else
  skip "file: the draft is the file's text, not the pasted text (needs the /works/:slug page)"
fi

# test "another kind of file is refused"
printf 'not text' > "$T/x.pdf"
upload_file "$T/x.pdf" "x.pdf"
assert_status 422 "file: a .pdf is a 422"
assert_contains "Only .txt and .md for now." "file: says Only .txt and .md for now."
get /works
assert_not_contains ">x<" "file: and nothing was saved"

# test "too big"
head -c 8000001 /dev/zero | tr '\0' 'a' > "$T/big.txt"
upload_file "$T/big.txt" "big.txt"
assert_status 422 "file: 8,000,001 bytes is a 422"
assert_contains "That file is too big (8MB limit)." "file: says That file is too big (8MB limit)."

# test "an empty file"
printf '  \n ' > "$T/empty.txt"
upload_file "$T/empty.txt" "empty.txt"
assert_status 422 "file: an empty file is a 422"
assert_contains "no text there yet" "file: and says there is no text there yet"

# describe "no file chosen"
# a browser that submits the file input empty sends an empty filename
get /works/new
_curl POST /works/new -F "manuscript=@/dev/null;filename=" --form-string "work[title]=Pasted instead" -F "work[body]=<$D/kettle.md" ${CSRF:+--form-string "_csrf_token=$CSRF"}
assert_located "file: an empty file input falls back to the pasted text"

# describe "a POST with no token"
new_visitor no-token
_curl POST /works/new --form-string "work[title]=x" --form-string "work[body]=hello there"
assert_status 403 "csrf: a POST /works/new with no token is refused"

# describe "the form is markup"
new_visitor markup
get /works/new
assert_contains 'id="work_title"' "new: the title field"
assert_contains 'name="work[title]"' "new: named work[title]"
assert_contains 'id="work_intent"' "new: the intent field"
assert_contains 'id="work_body"' "new: the body field"
assert_contains "Paste the draft" "new: labelled Paste the draft"
assert_contains 'id="import-url"' "new: the fetch box"
assert_contains 'phx-submit="fetch"' "new: is an event form"
assert_contains "Read it off the web" "new: says Read it off the web"
assert_contains 'class="mg-btn">Continue</button>' "new: the Continue button"

# describe "fetching a page" (offline: only what is refused before any request)
ev fetch '{"url":"ftp://example.com/x"}' /works/new
assert_contains "That needs to be an http or https address." "fetch: a ftp address is refused"
ev fetch '{"url":"http://localhost/x"}' /works/new
assert_contains "That address points at a private network, so it will not be fetched." "fetch: localhost is refused"
ev fetch '{"url":"http://192.168.1.1/x"}' /works/new
assert_contains "private network" "fetch: a private address is refused"
ev fetch '{"url":"   "}' /works/new
assert_status 200 "fetch: a blank address does nothing"
assert_not_contains "words from" "fetch: and says nothing"
ev validate '{"work":{"title":"Typed","intent":"why","body":"my words"}}' /works/new
assert_status 200 "validate: answers"
assert_contains 'value=\"Typed\"' "validate: the typed title is echoed"
get /works/new
assert_not_contains 'value="Typed"' "validate: a page load starts empty again"

# ================================= work_tree_test ==============================
# describe the /works page as a file tree
new_visitor tree
get /works
assert_status 200 "tree: /works opens for a new visitor"
assert_contains "Nothing here yet. Bring the draft in the drawer." "tree: an empty page says so"
assert_not_contains 'id="tree"' "tree: and carries no tree"
assert_contains 'id="new-folder"' "tree: the new-folder form is there"

upload_text "Alpha draft" "$BODY300"
upload_text "Beta draft" "$BODY300"
get /works
assert_contains "Alpha draft" "tree: with no folders it still lists the drafts"
assert_contains "Beta draft" "tree: ... all of them"
assert_contains 'id="tree"' "tree: with drafts it carries the tree"
assert_contains 'phx-hook="Tree"' "tree: wired to the Tree hook"
assert_contains 'data-drop-id="root"' "tree: the root is a drop zone"
assert_matches 'Your drafts</h1><span class="mg-meta">2</span>' "tree: the count in the header is every draft"
A="$(work_id 'Alpha draft')"; B="$(work_id 'Beta draft')"
assert_num "$A" "tree: the draft rows carry their ids"

# test "adding a folder puts an empty bucket on the page"
ev new_folder '{"name":"Case files"}' /works
assert_status 200 "new_folder: answers"
assert_contains "Case files" "new_folder: the folder is on the page"
assert_contains "empty — drag a draft here" "new_folder: and is empty"
get /works
F="$(folder_id 'Case files')"
assert_num "$F" "new_folder: and has an id"
assert_contains 'class="mg-tree-hint"' "new_folder: with a folder the drag hint shows"

# test "a blank folder name is ignored rather than made"
ev new_folder '{"name":"   "}' /works
get /works
assert_eq "$(grep -o 'class="mg-fold"' "$BODY_F" | wc -l | tr -d ' ')" "1" "new_folder: a blank name makes nothing"

# test "a duplicate folder name says so instead of appearing twice"
ev new_folder '{"name":"Case files"}' /works
assert_contains "already a folder with that name" "new_folder: a duplicate says so"
get /works
assert_eq "$(grep -o 'class="mg-fold"' "$BODY_F" | wc -l | tr -d ' ')" "1" "new_folder: and is not made twice"

# test "dropping a draft on a folder files it there"
ev move "{\"kind\":\"work\",\"id\":\"$A\",\"into\":\"$F\"}" /works
assert_status 200 "move: a draft dropped on a folder answers"
get /works
assert_matches "class=\"mg-fkids\" style=\"--rail:0\\.95rem\"><div id=\"work-$A\"" "move: the draft is inside the folder"
assert_matches "id=\"folder-$F\".*id=\"work-$A\".*id=\"work-$B\"" "move: and the other draft is still outside it"

# test "dropping it back on the root takes it out again"
ev move "{\"kind\":\"work\",\"id\":\"$A\",\"into\":\"root\"}" /works
get /works
assert_matches "class=\"mg-fkids\" style=\"--rail:0\\.95rem\"><p class=\"mg-fempty\"" "move: dropped on the root, the folder is empty again"

# test "dropping a folder on a folder nests it"
ev new_folder '{"name":"Outer"}' /works
ev new_folder '{"name":"Inner"}' /works
get /works
OUT="$(folder_id 'Outer')"; INN="$(folder_id 'Inner')"
ev move "{\"kind\":\"folder\",\"id\":\"$INN\",\"into\":\"$OUT\"}" /works
get /works
assert_matches "id=\"folder-$OUT\".*class=\"mg-fkids\" style=\"--rail:0\\.95rem\"><div id=\"folder-$INN\"" "move: the folder is nested"
assert_matches "data-drop-id=\"$INN\" style=\"padding-left:1\\.65rem\"" "move: and indented one level"

# test "dropping a folder into its own child is refused out loud"
ev move "{\"kind\":\"folder\",\"id\":\"$OUT\",\"into\":\"$INN\"}" /works
assert_contains "A folder cannot go inside itself." "move: a folder into its own child is refused out loud"
get /works
assert_matches "id=\"folder-$OUT\".*class=\"mg-fkids\" style=\"--rail:0\\.95rem\"><div id=\"folder-$INN\"" "move: and nothing changed"
ev move "{\"kind\":\"folder\",\"id\":\"$OUT\",\"into\":\"$OUT\"}" /works
assert_contains "A folder cannot go inside itself." "move: a folder into itself is the same refusal"

# test "collapsing a folder hides what is in it without moving anything"
ev move "{\"kind\":\"work\",\"id\":\"$A\",\"into\":\"$F\"}" /works
assert_contains "Alpha draft" "toggle: a draft in an open folder is shown"
ev toggle "{\"id\":\"$F\"}" /works
assert_not_contains "Alpha draft" "toggle: collapsing hides what is in it"
assert_contains "aria-label=\\\"Expand\\\"" "toggle: and the twist offers Expand"
ev toggle "{\"id\":\"$F\"}" /works
assert_contains "Alpha draft" "toggle: a second toggle shows it again"
get /works
assert_matches "id=\"work-$A\"" "toggle: nothing was moved"
ev toggle "{\"id\":\"$F\"}" /works
get /works
assert_contains "Alpha draft" "toggle: a page load starts with every folder open"

# test "renaming a folder keeps its contents"
ev rename_start "{\"id\":\"$F\"}" /works
assert_contains "rename-$F" "rename: rename_start shows the form"
assert_contains 'phx-key' "rename: with Escape bound"
ev rename_cancel '{"key":"Escape"}' /works
assert_not_contains "rename-$F" "rename: rename_cancel puts the name back"
ev rename_start "{\"id\":\"$F\"}" /works
ev rename "{\"folder_id\":\"$F\",\"name\":\"Briefs\"}" /works
assert_contains "Briefs" "rename: the new name is shown"
assert_not_contains "Case files" "rename: and the old one is gone"
assert_not_contains "rename-$F" "rename: and the form is closed"
get /works
assert_matches "id=\"folder-$F\".*id=\"work-$A\"" "rename: the contents are kept"
ev rename_start "{\"id\":\"$F\"}" /works
ev rename "{\"folder_id\":\"$F\",\"name\":\"Outer\"}" /works
assert_contains "already a folder with that name" "rename: a name that clashes says so"
assert_contains "rename-$F" "rename: and the form stays open"
ev rename_cancel '{}' /works

# test "deleting a folder from the page leaves the drafts on it"
ev delete_folder "{\"id\":\"$F\"}" /works
assert_contains "Folder gone. What was in it moved up a level." "delete_folder: says what happened"
assert_contains "Alpha draft" "delete_folder: the draft is still on the page"
assert_not_contains "Briefs" "delete_folder: the folder is gone"
get /works
assert_matches "id=\"work-$A\"" "delete_folder: the draft is back at the root"

# test "deleting a draft"
ev delete "{\"id\":\"$B\"}" /works
assert_contains "Deleted." "delete: says Deleted."
assert_not_contains "Beta draft" "delete: and the draft is gone"
get /works
assert_not_contains "Beta draft" "delete: from the page, too"
assert_contains "Alpha draft" "delete: the other draft is untouched"

# test "someone else's draft and folder are not theirs to move or delete"
new_visitor tree-other
get /works
ev move "{\"kind\":\"work\",\"id\":\"$A\",\"into\":\"root\"}" /works
ev delete "{\"id\":\"$A\"}" /works
ev delete_folder "{\"id\":\"$OUT\"}" /works
assert_not_contains "Deleted." "other: a stranger's delete does nothing"
assert_not_contains "Folder gone" "other: nor does deleting a folder"
new_visitor tree
get /works
assert_contains "Alpha draft" "other: and the owner still has the draft"
assert_contains "Outer" "other: and the folder"

# describe "the offer to file drafts by case"
new_visitor tree-case
get /works
upload_text "Opinion" "$BODY300"
upload_text "Dissent" "$BODY300"
get /works
assert_not_contains "file them by case" "backfill: no offer while nothing says which case"
if command -v sqlite3 >/dev/null 2>&1 && [ -f "${MARGINALIA_DB:-}" ]; then
  OP="$(work_id Opinion)"; DI="$(work_id Dissent)"
  sqlite3 "$MARGINALIA_DB" "PRAGMA busy_timeout=5000; UPDATE works SET collection = 'Demo v. Example', collection_role = 'opinion' WHERE id = $OP; UPDATE works SET collection = 'Demo v. Example', collection_role = 'dissent' WHERE id = $DI;" >/dev/null
  get /works
  assert_contains "file them by case" "backfill: it appears while there is something to file"
  assert_contains "2 of these already say which case" "backfill: and counts them"
  ev backfill '{}' /works
  assert_contains "Filed 2 drafts by case." "backfill: says how many it filed"
  assert_not_contains "file them by case" "backfill: and the offer is gone"
  get /works
  assert_contains ">Cases<" "backfill: builds Cases"
  assert_contains ">Demo v. Example<" "backfill: and the case under it"
  assert_matches "id=\"folder-[0-9]+\".*>Demo v\\. Example<.*id=\"work-$DI\".*id=\"work-$OP\"" "backfill: with both drafts in it"
  ev backfill '{}' /works
  assert_not_contains "Filed" "backfill: a second time files nothing"
else
  skip "backfill: needs sqlite3 and MARGINALIA_DB to give a draft a case"
fi

# describe "events the page does not have"
new_visitor tree-bad
get /works
ev frobnicate '{}' /works
assert_status 500 "events: an event /works does not have is a 500, not a plausible answer"
