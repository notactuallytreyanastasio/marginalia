#!/usr/bin/env bash
# 20_works.sh: guests, the draft list, uploading a draft (form and plain POST).
# SKELETON. Runs only when "20_works.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md part 9 and 8): guest_upload_test (13), work_upload_fallback_test (8).
# Planned for this file but not yet written, see IMPLEMENTED for titles: work_tree_test (15, the
# /works folder tree: new_folder, move, toggle, rename), step_links_test (5), import_flow_test (25,
# /import wizard against a fake GitHub: needs a fake_github.blimp next to fake_llm.blimp).
#
# Event names (ev ...) are the Elixir handler names; the web agent for /works should confirm.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

D="$E2E_DIR/fixtures/drafts"
PASS='hello world!'
BODY300="$(words 300)"

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

# test "a guessed slug gets nothing"
get /works/1
assert_redirect_to "/works" "guest: /works/1 goes back to /works"
get /works/1/graph.json
assert_status 404 "guest: /works/1/graph.json is a 404"

# test "the owner sees it as theirs, with a link to hand out"
new_visitor guest-a
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
# test "a guest becomes a real user and keeps everything they uploaded"
new_visitor claim
upload_text "Kept" "$BODY300"
CLAIM_SLUG="$(draft_slug)"
CLAIMED="claimed$RANDOM@example.com"
register "$CLAIMED" "a-long-enough-password"
get /works
assert_contains "Kept" "claim: the work is still listed after the guest signs up"
new_visitor claim-login
login "$CLAIMED" "a-long-enough-password"
assert_redirect_to "/" "claim: the claimed account logs in with its new password"
get /works
assert_contains "Kept" "claim: the same work is there under the real account"
assert_not_contains "Keep my drafts" "claim: they are no longer a guest"
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

# describe "POST /works/new"
# test "saves the draft and goes to it, rather than 404ing"
new_visitor fallback-user
ensure_user "$(new_email)" "$PASS"
upload_text "Pasted" "$(cat "$D/kettle.md")" ""
S="$(draft_slug)"
assert_redirect_to "/works/$S" "fallback: POST /works/new redirects to /works/<slug>"
get "/works/$S"
assert_status 200 "fallback: the page it sends them to is there"
assert_contains "Pasted" "fallback: and it shows the title"
# test "a visitor with no account at all gets one on the way in"
new_visitor fallback-anon
upload_text "Anon" "$(cat "$D/kettle.md")"
S2="$(draft_slug)"
assert_matches '^/works/.' "fallback: an anonymous POST redirects to a draft ($LOCATION)"
get "/works/$S2"
assert_contains "Anon" "fallback: the anonymous draft was saved under a guest"
# test "an untitled draft still saves"
new_visitor fallback-untitled
upload_text "   " "$(cat "$D/kettle.md")"
get "/works/$(draft_slug)"
assert_contains "Untitled draft" "fallback: a blank title becomes Untitled draft"

# describe "when the plain POST cannot be saved"
# test "an empty draft says so and says why a file did not arrive"
new_visitor fallback-empty
upload_text "Nothing" "   "
assert_status 422 "fallback: an empty draft is a 422"
assert_contains "There&#39;s no text there yet" "fallback: says There's no text there yet"
assert_contains "Attaching a file needs JavaScript" "fallback: says Attaching a file needs JavaScript"
assert_not_contains "404" "fallback: and is not a 404 page"
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
