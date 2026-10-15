#!/usr/bin/env bash
# 60_cuts.sh: the readings. /cuts (every folder, the reading it has, the read button) and
# /cuts/:id (the weave, the members, the waiting state, the answer, focus, again, delete).
#
# Source: notes/web-cuts-links-users.md section 1 (CutLive.Index and CutLive.Show). notes/tests.md
# has no LiveView test for these pages (cuts_test.exs is the domain, ported in the cuts library),
# so the assertions are the section's behaviours. Folders and drafts are seeded with sqlite3 in
# the app's database (the pages that make them, /works, are another group); users register and
# log in through the real pages.
#
# The read is a forked job calling the fake LLM, whose reply for the cut prompt is
# fixtures/llm/"Say what they amount to together.cut.json" (the needle is a phrase of the cut's
# system prompt). The waiting state is asserted on a cut seeded as `reading` with a `running`
# run row and no job, because a real job against the fake finishes in milliseconds.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

PASS='hello world!'
sq() { sqlite3 -cmd '.timeout 5000' "$MARGINALIA_DB" "$@"; }

command -v sqlite3 >/dev/null 2>&1 || { skip "cuts: needs the sqlite3 command to seed folders and drafts"; exit 0; }

# poll PATH: the refetch blimp.js makes while a [data-poll] element is on the page
poll() { _curl GET "$1" -H 'x-requested-with: blimp' -H 'accept: application/json'; }

# seed_work USER_ID FOLDER_ID TITLE BODY: a draft in a folder, one section holding BODY
seed_work() {
  local slug="cuts-$RANDOM$RANDOM$RANDOM"
  sq "INSERT INTO works (user_id, title, body, word_count, slug, folder_id) VALUES ($1, '$3', '$4', 12, '$slug', $2);
      INSERT INTO sections (work_id, ordinal, title, body, word_count) VALUES (last_insert_rowid(), 1, '$3', '$4', 12);"
}

# ======================= a stranger ===========================================
new_visitor stranger
get /cuts
assert_status 200 "cuts: /cuts is open to a visitor"
assert_cookie _marginalia_key "cuts: and gives them a session"
assert_contains "Readings" "cuts: the page is titled Readings"
assert_contains "0 of 0 folders read" "cuts: a stranger has no folders read"
assert_contains "A reading is what a folder says that none of its drafts says alone." "cuts: and is told what a reading is"
assert_contains 'class="mg-btn sm ghost ml-auto">Folders</a>' "cuts: with the way to the folders"
get /cuts/1
assert_status 303 "cuts: a reading a stranger does not have is not shown"
assert_redirect_to /cuts "cuts: it sends them to the list"
get /cuts/abc
assert_status 404 "cuts: an id that is not a number is a 404"

# ======================= the owner's folders ====================================
OWNER="cuts-owner$RANDOM@example.com"
new_visitor owner
ensure_user "$OWNER" "$PASS"
UID1="$(sq "SELECT id FROM users WHERE email = '$OWNER'")"
sq "INSERT INTO folders (name, user_id) VALUES ('Vigils', $UID1);"
F1="$(sq "SELECT id FROM folders WHERE name = 'Vigils' AND user_id = $UID1")"
seed_work "$UID1" "$F1" "Kettle" "The kettle goes cold before anyone admits the news has come."
seed_work "$UID1" "$F1" "Lighthouse" "The lamp turns all night and nobody on the shore looks up."
sq "INSERT INTO folders (name, user_id) VALUES ('Empty', $UID1);"
F2="$(sq "SELECT id FROM folders WHERE name = 'Empty' AND user_id = $UID1")"

get /cuts
assert_status 200 "index: the owner gets the list"
assert_contains "0 of 2 folders read" "index: two folders, none read"
assert_contains "id=\"cut-row-$F1\" class=\"cut-row\" style=\"padding-left:0.0rem\"" "index: a row per folder, with an id the morph can key on"
assert_contains "class=\"text-[1.05rem] text-[var(--mg-dim)]\">Vigils</span>" "index: a folder with no reading is dim text, not a link"
assert_contains "2 drafts" "index: and says how many drafts it holds"
assert_contains "phx-click=\"read\" phx-value-folder=\"$F1\">read</button>" "index: with a read button"
assert_contains "Read from the inside out." "index: and the note on reading from the inside out"
assert_not_contains "mg-badge ink" "index: nothing is marked read yet"
assert_not_contains "data-poll" "index: the index does not poll"

# a folder that is not yours is refused, and the list stays
new_visitor other
ensure_user "cuts-other$RANDOM@example.com" "$PASS"
get /cuts
ev read "{\"folder\":\"$F1\"}" /cuts
assert_contains "That folder is not yours." "read: someone else's folder is refused with a flash"
assert_contains '"regions"' "read: and the answer is the list again"
assert_eq "$(sq 'SELECT count(*) FROM cuts')" "0" "read: and no reading was made"
get /cuts
assert_contains "0 of 0 folders read" "index: the other user sees none of the owner's folders"

# ======================= opening a reading ========================================
new_visitor owner
login "$OWNER" "$PASS"
get /cuts
ev read "{\"folder\":\"$F1\"}" /cuts
assert_contains '"redirect":"/cuts/' "read: the event sends the browser to the reading"
CUT="$(sed -n 's#.*"redirect":"/cuts/\([0-9]*\)".*#\1#p' "$BODY_F")"
assert_eq "$(sq "SELECT status FROM cuts WHERE id = $CUT")" "draft" "read: the reading starts out queued"
assert_eq "$(sq "SELECT title FROM cuts WHERE id = $CUT")" "Vigils" "read: and is titled for the folder"
ev read "{\"folder\":\"$F1\"}" /cuts
assert_contains "\"redirect\":\"/cuts/$CUT\"" "read: asking again is the same reading"
assert_eq "$(sq 'SELECT count(*) FROM cuts')" "1" "read: still one reading"
ev read '{"folder":"abc"}' /cuts
assert_status 500 "read: a folder that is not a number stops the event"

# ======================= the waiting state ============================================
# a cut that is mid-read with a job running, and no job: the page can only wait
sq "UPDATE cuts SET status = 'reading', question = 'What keeps them up?' WHERE id = $CUT;
    INSERT INTO runs (key, status, started_at) VALUES ('cut:$CUT', 'running', datetime('now'));"
get "/cuts/$CUT"
assert_status 200 "waiting: the reading is served"
assert_contains "Reading this folder. One call, and it is the slow kind." "waiting: it says the read is running"
assert_contains 'data-poll="2"' "waiting: and polls every two seconds"
assert_contains "<p class=\"cut-ask\">What keeps them up?</p>" "waiting: the question is shown"
assert_contains "id=\"weave-$CUT\" class=\"cut-weave\" phx-hook=\"Weave\" phx-update=\"ignore\" data-status=\"reading\"" "waiting: the weave is there, for the hook, before any answer"
assert_contains "&quot;label&quot;:&quot;Kettle&quot;" "waiting: and carries the members it will try pairs of"
assert_contains 'data-links="[]"' "waiting: with no pairs drawn yet"
assert_contains '<span class="l">Lighthouse</span>' "waiting: a button per member, before the answer"
assert_not_contains "Thesis" "waiting: no thesis yet"
poll "/cuts/$CUT"
assert_contains '"regions"' "waiting: the poll is answered with the region"
assert_contains 'data-poll=\"2\"' "waiting: and the region still carries data-poll"
assert_contains "Reading this folder." "waiting: and the same words"
ev again '{}' "/cuts/$CUT"
assert_contains "Reading this folder." "waiting: reading again while a job runs starts nothing and waits"
assert_eq "$(llm_calls)" "0" "waiting: no model call has been made"

# ======================= the answer ========================================================
sq "DELETE FROM runs WHERE key = 'cut:$CUT'; UPDATE cuts SET status = 'draft' WHERE id = $CUT;"
get "/cuts/$CUT"
assert_status 200 "read: a queued reading opened by its URL is served"
assert_waits "/cuts/$CUT" "Both wait for something nobody will name." 20 "read: the background read finishes and the page shows the through-line"
assert_contains '<h2 class="cut-h">Thesis</h2>' "read: with a Thesis heading"
assert_contains '<p class="cut-thesis">Both drafts keep a vigil for news that has already arrived.</p>' "read: and the thesis"
assert_contains '<h2 class="cut-h">Through-lines</h2>' "read: the through-lines"
assert_contains '<h2 class="cut-h">Tensions</h2>' "read: the tensions"
assert_contains "One waits indoors and the other in the open." "read: a tension"
assert_contains "<cite>Kettle</cite>" "read: a quote is cited by the member's title"
assert_contains "The lamp turns all night" "read: and the quote is the draft's own wording"
assert_contains '<h2 class="cut-h">What this does not show</h2>' "read: what the reading does not show"
assert_contains "Nothing here says what the news was." "read: in the model's words"
assert_contains "2 claims dropped for quotes that could not be found" "read: the claim with a made-up quote was dropped, and counted"
assert_not_contains "Made up, so it is dropped." "read: and is not shown"
assert_not_contains "data-poll" "read: and the page stops polling"
assert_contains 'data-status="read"' "read: the weave knows it is read"
assert_contains 'data-links="[{&quot;a&quot;:1,&quot;b&quot;:2,&quot;kind&quot;:&quot;thread&quot;},{&quot;a&quot;:1,&quot;b&quot;:2,&quot;kind&quot;:&quot;tension&quot;}]"' "read: and the pairs that held, a thread and a tension"
assert_contains 'phx-click="again">read again</button>' "read: a read again button"
assert_contains 'data-confirm="Delete this reading?"' "read: and a delete button that asks first"
assert_not_contains "This folder has changed since it was read." "read: the reading is current"
assert_eq "$(sq "SELECT status FROM cuts WHERE id = $CUT")" "read" "read: the row says read"
assert_eq "$(sq "SELECT status FROM runs WHERE key = 'cut:$CUT'")" "done" "read: and the run is done"
assert_eq "$(llm_calls)" "1" "read: one model call, the cut prompt"
assert_llm_log_contains "Say what they amount to together.cut.json" "read: and the fake picked the cut reply by its needle"

# ======================= focus ===============================================================
get "/cuts/$CUT"
ev focus '{"n":"1"}' "/cuts/$CUT"
assert_contains 'cut-member on' "focus: the focused member's button is lit"
assert_contains 'Both wait for something nobody will name.' "focus: the claims that rest on it stay"
ev focus '{"n":"3"}' "/cuts/$CUT"
assert_not_contains 'Both wait for something nobody will name.' "focus: a member nothing rests on leaves no claims"
assert_not_contains '<h2 class=\"cut-h\">Through-lines</h2>' "focus: and no empty group heading"
ev focus '{"n":"3"}' "/cuts/$CUT"
assert_not_contains 'cut-member on' "focus: the same member again lets go"
assert_contains 'Both wait for something nobody will name.' "focus: and the claims come back"
ev focus '{"n":"2"}' "/cuts/$CUT"
poll "/cuts/$CUT"
assert_contains 'cut-member on' "focus: the focus is kept across the poll"
get "/cuts/$CUT"
assert_not_contains 'cut-member on' "focus: and forgotten on a fresh visit"

# ======================= the index after a read ================================================
get /cuts
assert_contains "1 of 2 folders read" "index: one of two folders read"
assert_contains "<span class=\"mg-badge ink mr-2\">read</span>" "index: the read folder is badged"
assert_contains "<a href=\"/cuts/$CUT\"" "index: and links to its reading"
assert_contains "<span>· 1 through-lines</span>" "index: with its through-lines counted"
assert_contains "phx-value-folder=\"$F1\">read again</button>" "index: and offers read again"

# ======================= stale ==================================================================
seed_work "$UID1" "$F1" "Harbour" "The ferry is late and the quay keeps its own counsel."
get "/cuts/$CUT"
assert_contains "This folder has changed since it was read." "stale: a folder that gained a draft says so"
assert_contains 'class="mg-btn sm ghost ml-2" phx-click="again">read again</button>' "stale: with a way to read again"

# ======================= reading again ===============================================================
ev again '{}' "/cuts/$CUT"
assert_contains '"regions"' "again: the event answers with the region"
assert_waits "/cuts/$CUT" 'data-status="read"' 20 "again: the second read finishes"
assert_eq "$(llm_calls)" "2" "again: and it was a second model call"
assert_eq "$(sq "SELECT count(*) FROM cuts")" "1" "again: into the same reading"
assert_contains "<span class=\"mg-meta\">" "again: the page is whole"
assert_not_contains "This folder has changed since it was read." "again: and is current again"

# ======================= a folder with nothing in it ====================================================
get /cuts
ev read "{\"folder\":\"$F2\"}" /cuts
CUT2="$(sed -n 's#.*"redirect":"/cuts/\([0-9]*\)".*#\1#p' "$BODY_F")"
get "/cuts/$CUT2"
assert_waits "/cuts/$CUT2" "this folder holds nothing to read" 20 "failed: an empty folder fails with the reason"
assert_contains '<p class="cut-err mt-6">this folder holds nothing to read' "failed: in the failure paragraph"
assert_contains 'phx-click="again">try again</button>' "failed: with try again"
assert_not_contains "data-poll" "failed: and no polling"
assert_not_contains 'class="cut-weave"' "failed: and no weave, for there are no members"
assert_eq "$(llm_calls)" "2" "failed: no model call was made for it"
get /cuts
assert_contains "<span>· failed</span>" "failed: the index says failed"

# ======================= whose reading it is ==========================================================
new_visitor other
ensure_user "cuts-other2$RANDOM@example.com" "$PASS"
get "/cuts/$CUT"
assert_status 303 "owner: another user cannot open the reading"
assert_redirect_to /cuts "owner: and is sent to their own list"
get /cuts
assert_contains "No such reading." "owner: with a flash that says so"
ev delete '{}' "/cuts/$CUT"
assert_contains '"redirect":"/cuts"' "owner: and cannot delete it either"
assert_eq "$(sq 'SELECT count(*) FROM cuts')" "2" "owner: both readings are still there"

# ======================= delete ===============================================================================
new_visitor owner
login "$OWNER" "$PASS"
get "/cuts/$CUT"
ev delete '{}' "/cuts/$CUT"
assert_contains '"redirect":"/cuts"' "delete: the event sends the browser to the list"
assert_eq "$(sq 'SELECT count(*) FROM cuts')" "1" "delete: the reading is gone"
assert_eq "$(sq 'SELECT count(*) FROM works')" "3" "delete: and its drafts are not"
get /cuts
assert_contains "Reading deleted." "delete: the list says so"
get "/cuts/$CUT"
assert_redirect_to /cuts "delete: and the reading is no longer there"
