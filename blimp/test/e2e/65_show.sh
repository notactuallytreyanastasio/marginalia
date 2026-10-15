#!/usr/bin/env bash
# 65_show.sh: the work page, /works/:slug: the read view with its notes in the margin, the controls
# that start the read, the rewrite panel, the editor, the summaries, the tour and the walkthrough,
# the tab and drawer navigation, and the three downloads beside it.
#
# Source tests (notes/tests.md parts 6 to 8): confirm_gate_test (6), progress_test (4),
# live_beats_test (4), read_view_test (7), read_changes_test (5), rewrite_apply_test (1),
# rewrite_panel_test (8), note_deck_test (5), inline_thread_test (9), tour_test (7),
# walkthrough_live_test (9), work_tabs_test (7), summary_vault_test (5), changes_tab_test (7),
# and the graph controller of part 9. note_piles_test is a pure function (a Temper test).
#
# The LiveView tests held a socket and sent messages to it; here an event is `POST /ev/<name>` and
# the page is fetched afterwards, so most assertions read the page after the event. The model is
# fake_llm: the read (beats, spine, weave), the rewrite and the summary are answered by fixtures
# under fixtures/llm/ whose names start with a phrase of each pass's prompt. A job is forked, so
# every wait is a poll of the page for a sentence the job's answer puts there.
#
# Named 65 and not 50 because 60_cuts.sh counts the model calls in the shared log and the
# drafts in the database from zero; this file makes both, so it runs after that one.
#
# Not asserted here: the Graph, Spine, Threads, Changes, Trace and Prompts views and the chat
# drawer (other authors' files), and the margin layout (a browser's).
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

D="$E2E_DIR/fixtures/drafts"
PASS='hello world!'
OWNER_MAIL="owner@example.com"   # e2e.sh: OWNER_EMAIL, the account the deploy belongs to

# wait_lacks PATH TEXT SECONDS DESC: poll until the page no longer contains TEXT
wait_lacks() {
  local path="$1" text="$2" secs="$3" i=0 n
  n=$((secs * 2))
  while [ "$i" -lt "$n" ]; do
    get "$path"
    grep -qF -- "$text" "$BODY_F" || { _ok "$4"; return 0; }
    sleep 0.5; i=$((i + 1))
  done
  _bad "$4" "'$text' was still on $path after $secs s"
}

# first_of REGEX: the first match of an extended regex in the last body
first_of() { grep -oE -- "$1" "$BODY_F" | head -1; }
section_id() { first_of 'phx-value-section="[0-9]+"' | sed 's/[^0-9]//g'; }
nth_block() { grep -oE 'id="block-s[0-9]+p[0-9]+"' "$BODY_F" | sed -n "$1p" | sed -e 's/id="block-//' -e 's/"//'; }

assert_located() {
  case "$STATUS:$LOCATION" in
    30[0-9]:/works/?*|30[0-9]:http*/works/?*) _ok "$1 ($LOCATION)" ;;
    *) _bad "$1" "expected a redirect to /works/<slug>, got status $STATUS, Location: $LOCATION" ;;
  esac
}

SENTENCE='The kettle went cold on the counter, and nobody moved to fill it again.'

# ============================== the confirm gate ==============================
new_visitor owner
ensure_user "$(new_email)" "$PASS"
upload_draft "$D/kettle.md" "The Kettle"
SLUG="$(draft_slug)"
assert_located "gate: uploading a draft lands on /works/<slug>"

get "/works/$SLUG"
assert_status 200 "gate: the draft's page opens"
assert_contains "Before it reads" "gate: an unread draft shows the gate"
assert_matches 'Read it — [0-9]+ sections' "gate: the read can be started"
assert_contains 'phx-click="start_read"' "gate: the button starts the read"
assert_not_contains "Reading your draft" "gate: nothing is reading yet"
assert_not_contains 'id="read-rail"' "gate: the read view is not drawn before the read"
assert_contains "noindex, nofollow" "page: it asks not to be indexed"
assert_contains "Copy link" "page: the owner has a link to hand out"

new_visitor reader
get "/works/$SLUG"
assert_status 200 "gate: a link-holder can open the draft"
assert_not_contains "Read it —" "gate: someone else's draft offers no button at all"
assert_contains "reading someone&#39;s draft" "page: a link-holder is told whose draft it is"
assert_not_contains "Copy link" "page: a link-holder has no Copy link"
ev start_read '{}' "/works/$SLUG"
assert_contains "You can read it, not change it" "gate: a link-holder cannot start the read"
get "/works/$SLUG"
assert_contains "Before it reads" "gate: and the draft is still unread"

# ================================== the read ==================================
new_visitor owner
get "/works/$SLUG"
ev start_read '{}' "/works/$SLUG"
assert_status 200 "read: pressing Read it answers"
assert_contains "Reading your draft" "read: the answer shows the progress at once"
assert_contains 'data-poll=\"2\"' "read: and asks the client to poll"

get "/works/$SLUG"
assert_matches 'Reading your draft|id="read-rail"' "read: the page shows the read, or what it found"
assert_contains "The page, with its notes in the margin" "tour: the first visit to a tab explains it"
get "/works/$SLUG"
assert_not_contains "The page, with its notes in the margin" "tour: the second visit does not"

wait_lacks "/works/$SLUG" "Reading your draft" 90 "read: the read finishes and the progress goes"
assert_not_contains "data-poll" "read: a page with nothing running does not poll"
assert_contains 'id="read-rail"' "read: the page is drawn"
assert_contains "They set the scene at the window" "read: a beat is in the margin"
assert_matches 'id="anchor-s[0-9]+p[0-9]+"' "read: the anchored span is marked, with the id its note points at"
assert_contains "for an hour before anyone noticed.</mark>" "read: the mark closes on the quoted words"
assert_contains 'class="mg-tab on" phx-click="set_only" phx-value-only="all"' "filters: it opens on everything"
assert_matches 'class="mg-tick" phx-click="open_thread"' "read: every paragraph has a tick"
assert_matches 'mg-note-slot (beat|pays_off|develops|requires|tension)' "read: the notes are in slots in the rail"
assert_contains 'id="read-body" phx-hook="SummaryVault" data-editable="true"' "read: the owner's prose can be edited"
assert_not_contains ">Changes<" "changes: the tab is not offered on a draft nobody has changed"
assert_not_contains "Show what changed" "changes: nor the toggle"
assert_not_contains "mg-read mt-6 collapsed" "drawer: the rail is not collapsed while it is shut"

# ================================== filters ==================================
ev set_only '{"only":"tensions"}' "/works/$SLUG?view=read"
assert_status 200 "filters: choosing tensions answers"
get "/works/$SLUG?view=read"
assert_not_contains "They set the scene at the window" "filters: trimming to tensions hides the beats"
assert_contains "She had been standing at the window for an hour" "filters: and the prose is still there"
assert_contains 'class="mg-tab on" phx-click="set_only" phx-value-only="tensions"' "filters: the chosen filter is lit"
ev set_only '{"only":"all"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "They set the scene at the window" "filters: all puts the beats back"

# ============================ tabs, the drawer, the url ============================
ev set_view '{"view":"spine"}' "/works/$SLUG?view=read"
assert_contains '"redirect":"/works/'"$SLUG"'?view=spine"' "tabs: choosing a tab goes to the address with the view in it"
get "/works/$SLUG?view=spine"
assert_status 200 "tabs: the spine tab opens by direct link"
assert_contains 'class="mg-tab on" phx-click="set_view" phx-value-view="spine"' "tabs: and is lit"
ev set_view '{"view":"nonsense"}' "/works/$SLUG?view=spine"
assert_contains 'view=read' "tabs: an unknown view is the page"
get "/works/$SLUG?view=nonsense"
assert_contains 'id="read-rail"' "tabs: asked for directly, an unknown view is the page, not a report about it"
get "/works/$SLUG?view=trace"
assert_not_contains ">Trace<" "tabs: the owner's tabs are not the writer's"
assert_contains 'id="read-rail"' "tabs: asked for directly by someone else, Trace is the page"
ev toggle_chat '{}' "/works/$SLUG?view=read"
assert_contains '?view=read&chat=1' "drawer: Talk about it puts chat=1 in the address"
get "/works/$SLUG?view=read&chat=1"
assert_contains "mg-read mt-6 collapsed" "drawer: with it open the rail is collapsed, which turns click-to-edit off"
assert_contains "mg-drawer open" "drawer: the drawer is open"
assert_contains "mg-shifted" "drawer: and the page is shifted"
ev toggle_chat '{}' "/works/$SLUG?view=read&chat=1"
assert_contains '"redirect":"/works/'"$SLUG"'?view=read"' "drawer: pressing it again takes chat=1 out"

# ================================== threads ==================================
get "/works/$SLUG?view=read"
SEC="$(section_id)"
B1="$(nth_block 2)"
B2="$(nth_block 3)"
case "$SEC:$B1:$B2" in
  [0-9]*:s[0-9]*p[0-9]*:s[0-9]*p[0-9]*) _ok "threads: the tick names its section ($SEC) and the blocks their refs ($B1, $B2)" ;;
  *) _bad "threads: the tick names its section and the blocks their refs" "section '$SEC', blocks '$B1' '$B2'" ;;
esac
convos0="$(db_count conversations)"
ev open_thread '{"ref":"'"$B1"'","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "on this paragraph" "threads: opening one shows it under its paragraph"
assert_contains "What about this paragraph?" "threads: the owner has a box to ask in"
assert_contains 'class="mg-thread-panel"' "threads: exactly the panel"
if [ -n "$convos0" ]; then
  n1="$(db_count conversations)"
  ev close_thread '{}' "/works/$SLUG?view=read"
  ev open_thread '{"ref":"'"$B1"'","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
  assert_eq "$(db_count conversations)" "$n1" "threads: coming back to the same paragraph returns to the same thread"
  ev open_thread '{"ref":"'"$B2"'","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
  assert_eq "$(db_count conversations)" "$((n1 + 1))" "threads: a different paragraph gets its own"
else
  skip "threads: the same paragraph returns to the same thread (needs sqlite3)"
  skip "threads: a different paragraph gets its own (needs sqlite3)"
fi
ev open_thread '{"ref":"'"$B1"'","section":"'"$SEC"'","quote":"She had been standing at the window for an hour"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "on this passage" "threads: a selection pins the thread to the passage"
assert_contains "mg-thread-quote" "threads: and quotes it"
ev resolve_thread '{}' "/works/$SLUG?view=read"
ev close_thread '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'class="mg-thread-panel"' "threads: closing it takes the panel away"
assert_contains "has-thread" "threads: a paragraph with a thread says so"
ev open_thread '{"ref":"s1p999","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
assert_status 200 "threads: a paragraph that is not there makes no thread, and no crash"

# ================================= the rewrite =================================
ev suggest_rewrite '{"text":"'"$SENTENCE"'","ref":"'"$B1"'"}' "/works/$SLUG?view=read"
assert_status 200 "rewrite: asking answers at once, before the model has"
assert_contains "mg-rewrite working" "rewrite: the panel is open and working"
get "/works/$SLUG?view=read"
assert_matches 'Rewrites of (one line|[0-9]+ words)' "rewrite: the panel says how much it covers"
assert_contains 'id="rw-steer"' "rewrite: the steer box is there"
assert_contains "ask for something specific" "rewrite: with its prompt"
assert_waits "/works/$SLUG?view=read" "The kettle went cold; nobody refilled it." 60 "rewrite: the candidates arrive"
assert_contains "Cuts the gloss" "rewrite: each carries the move it makes"
assert_contains "Loses the again" "rewrite: and what it costs"
assert_contains "replace the passage with this →" "rewrite: and can replace the passage"
assert_contains "or edit it first →" "rewrite: or be edited first"
assert_not_contains "mg-rewrite working" "rewrite: the panel is no longer working"
assert_not_contains "data-poll" "rewrite: and the page stops polling"
ev preview_rewrite '{"i":"0"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains '<ins class="mg-swap">' "rewrite: hovering one shows it in the paragraph"
assert_contains '<del class="mg-cut">' "rewrite: against what goes"
ev clear_preview '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
[ "$(grep -o '<ins class="mg-swap">' "$BODY_F" | wc -l | tr -d ' ')" = 1 ] && _ok "rewrite: leaving puts the paragraph back (only the legend's ins is left)" || _bad "rewrite: leaving puts the paragraph back"
ev edit_block '{"ref":"'"$B1"'","seed":"Nobody moved, and the kettle went cold."}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains "That rewrite covers more than this paragraph" "rewrite: a seed that fits opens the box"
ev cancel_edit '{}' "/works/$SLUG?view=read"
ev close_rewrite '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'id="rewrite-panel"' "rewrite: closing the panel takes it away"

ev suggest_rewrite '{"text":"'"$SENTENCE"'","ref":"'"$B1"'"}' "/works/$SLUG?view=read"
assert_waits "/works/$SLUG?view=read" "Plainer verbs" 60 "rewrite: asking again brings the candidates again"
revs0="$(db_count revisions)"
ev apply_rewrite '{"i":"0"}' "/works/$SLUG?view=read"
assert_contains "Replaced." "rewrite: applying one says it was replaced"
get "/works/$SLUG?view=read"
assert_contains '>Changes<' "changes: the tab is offered once there is something to show"
assert_contains 'class="mg-applied"' "rewrite: the paragraph shows what it replaced, in place"
assert_not_contains 'id="rewrite-panel"' "rewrite: the panel is gone"
[ -n "$revs0" ] && assert_eq "$(db_count revisions)" "$((revs0 + 1))" "rewrite: a revision was written"
ev dismiss_applied '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'class="mg-applied"' "rewrite: the applied box is dismissable"
assert_contains "The kettle went cold; nobody refilled it." "rewrite: and the new line is in the draft"
assert_contains "Show what changed" "changes: the toggle is offered"
ev toggle_changes '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "mg-read-rail changes" "changes: with the toggle on the rail holds the before and after"
assert_contains "Cuts the gloss" "changes: and where the change came from"
[ "$(grep -o 'class="mg-read-rail' "$BODY_F" | wc -l | tr -d ' ')" = 1 ] && _ok "changes: one rail at a time, notes or changes" || _bad "changes: one rail at a time, notes or changes"
ev toggle_changes '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains "mg-read-rail changes" "changes: it toggles back"
get "/works/$SLUG?view=changes"
assert_status 200 "changes: the tab opens by direct link"

# ================================ editing a paragraph ================================
ev edit_block '{"ref":"'"$B2"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "mg-edit" "edit: clicking into a paragraph opens it for editing"
assert_contains 'id="edit-'"$B2"'"' "edit: the box has the paragraph's id"
revs1="$(db_count revisions)"
ev save_block '{"text":"   "}' "/works/$SLUG?view=read"
assert_contains "An empty paragraph is a deletion" "edit: an empty paragraph is refused"
ev save_block '{"text":"Nobody in the house said what they were waiting for."}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'id="edit-'"$B2"'"' "edit: saving closes the box"
assert_contains 'class="mg-applied"' "edit: the paragraph shows what it replaced"
ev dismiss_applied '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "Nobody in the house said what they were waiting for." "edit: and the paragraph is the new one"
[ -n "$revs1" ] && assert_eq "$(db_count revisions)" "$((revs1 + 1))" "edit: a revision was written"
ev edit_block '{"ref":"'"$B2"'"}' "/works/$SLUG?view=read"
ev cancel_edit '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'id="edit-' "edit: cancelling closes the box"

# ================================== summaries ==================================
get "/works/$SLUG?view=read"
assert_contains "Summarise this section" "summary: a section with no summary offers to make one"
assert_not_contains 'id="sumvault-' "summary: and has no vault"
assert_contains "Summarise the document" "summary: the whole document can be summarised"
ev summarise '{"ordinal":"1"}' "/works/$SLUG?view=read"
assert_status 200 "summary: asking answers"
assert_waits "/works/$SLUG?view=read" "A household waits at the window while the kettle goes cold" 60 "summary: the summary arrives"
assert_contains "data-sum-key=\"$SLUG:1\"" "summary: it carries a key naming the draft and the section"
assert_contains "data-sum-at=" "summary: and its time"
assert_contains 'id="sumvault-1" class="mg-sum-vault" phx-update="ignore"' "summary: the vault is left alone by the morph"
assert_contains "Summarise again" "summary: the button now says again"
assert_contains "Open as a draft" "summary: the summaries can be opened as a draft"
assert_contains "Draft it and compare" "summary: or compared"
assert_not_contains "the section has been edited since this was written" "summary: a current summary is not stale"

# ================================== the walkthrough ==================================
convos2="$(db_count conversations)"
ev start_walk '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains 'id="walk" phx-hook="Walk"' "walk: the overlay is on the page"
assert_contains "Nothing here is saved, and no model is called" "walk: and says it is safe"
assert_contains "Three rewrites, each with its cost" "walk: the owner's steps are all there"
ev open_thread '{"ref":"'"$B1"'","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains 'id="thread-0"' "walk: the thread it opens is never inserted"
[ -n "$convos2" ] && assert_eq "$(db_count conversations)" "$convos2" "walk: it wrote no conversation"
calls0="$(llm_calls)"
ev suggest_rewrite '{"text":"'"$SENTENCE"'","ref":"'"$B1"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "It changed how she saw her father." "walk: the rewrite is the fixed example"
assert_eq "$(llm_calls)" "$calls0" "walk: the model was not called"
ev edit_block '{"ref":"'"$B1"'"}' "/works/$SLUG?view=read"
ev save_block '{"text":"Never saved."}' "/works/$SLUG?view=read"
assert_contains "Nothing was saved" "walk: saving says it did nothing"
get "/works/$SLUG?view=read"
assert_not_contains "Never saved." "walk: the draft is as it was"
ev end_walk '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'id="walk"' "walk: ending it clears the overlay"
assert_not_contains 'id="thread-0"' "walk: and the thread it opened"
assert_not_contains 'id="rewrite-panel"' "walk: and the rewrite"
ev summarise '{"ordinal":"1"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains "The walkthrough does not call the model" "walk: outside the tour the same event does its job"

# ============================ someone holding the link ============================
new_visitor reader
get "/works/$SLUG?view=read"
assert_status 200 "reader: the draft opens"
assert_contains "She had been standing at the window" "reader: the prose is there"
assert_contains "They set the scene at the window" "reader: and the notes"
assert_contains 'data-editable="false"' "reader: the prose is not editable"
assert_not_contains "The whole document" "reader: no document box"
assert_not_contains "Summarise this section" "reader: no summary button"
assert_not_contains 'id="linkbox"' "reader: no link menu"
ev edit_block '{"ref":"'"$B1"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains 'id="edit-' "reader: edit_block opens nothing"
ev summarise '{"ordinal":"1"}' "/works/$SLUG?view=read"
assert_contains "This draft is someone else" "reader: summarise is refused"
ev suggest_rewrite '{"text":"'"$SENTENCE"'","ref":"'"$B1"'"}' "/works/$SLUG?view=read"
assert_contains "This draft is someone else" "reader: a rewrite is refused"
ev build_graph '{}' "/works/$SLUG?view=read"
assert_contains "You can read it, not change it" "reader: build_graph is refused"
ev set_provider '{"provider":"openai"}' "/works/$SLUG?view=read"
assert_contains "You can read it, not change it" "reader: set_provider is refused"
ev apply_rewrite '{"i":"0"}' "/works/$SLUG?view=read"
assert_contains "This draft is someone else" "reader: apply_rewrite is refused"
ev link_to '{"id":"1"}' "/works/$SLUG?view=read"
assert_contains "This draft is someone else" "reader: link_to is refused"
ev open_thread '{"ref":"s1p9999","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
assert_contains "This draft is someone else" "reader: a thread cannot be made"
ev open_thread '{"ref":"'"$B1"'","section":"'"$SEC"'"}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains "mg-thread-panel" "reader: a thread that exists can be read"
assert_not_contains "What about this paragraph?" "reader: with no box to ask in"
ev start_walk '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_not_contains "Three rewrites, each with its cost" "reader: a walkthrough leaves out the steps they cannot use"
assert_contains "The notes sit beside the line" "reader: and keeps the rest"

# ================================ the downloads ================================
new_visitor owner
get "/works/$SLUG/graph.json"
assert_status 200 "graph.json: anyone with the slug"
assert_header content-type 'application/json' "graph.json: is JSON"
assert_header content-disposition 'attachment; filename="the-kettle-graph.json"' "graph.json: is named after the draft"
assert_contains '"nodes"' "graph.json: holds the nodes"
assert_contains '"marginalia_type": "beat"' "graph.json: the beats among them"
assert_contains '"metadata_json"' "graph.json: with the metadata the lane tree reads"
get "/works/$SLUG/graph.dot"
assert_status 200 "graph.dot: opens"
assert_header content-type 'text/vnd.graphviz' "graph.dot: is graphviz"
assert_header content-disposition 'attachment; filename="the-kettle-graph.dot"' "graph.dot: is named after the draft"
assert_contains "digraph marginalia" "graph.dot: is a digraph"
get "/works/$SLUG/trace.json"
assert_status 200 "trace.json: the draft's owner"
assert_header content-disposition 'attachment; filename="the-kettle-trace.json"' "trace.json: is named after the draft"
assert_contains '"events"' "trace.json: holds the events"
new_visitor reader
get "/works/$SLUG/graph.json"
assert_status 200 "graph.json: a link-holder gets it too"
get "/works/$SLUG/trace.json"
assert_status 404 "trace.json: but not the trace, which does not travel with the link"
assert_contains "not found" "trace.json: the 404 says so"
get "/works/nothing-here/graph.json"
assert_status 404 "graph.json: an unknown slug is a 404"
get "/works/nothing-here/graph.dot"
assert_status 404 "graph.dot: an unknown slug is a 404"
get "/works/nothing-here"
assert_redirect_to "/works" "page: an unknown slug goes back to /works"
get "/works/1"
assert_redirect_to "/works" "page: the row id is not a slug"

# ================================ the deploy's owner ================================
new_visitor boss
ensure_user "$OWNER_MAIL" "$PASS"
get "/works/$SLUG?view=read"
assert_status 200 "boss: the owner of the deploy can read it"
assert_contains ">Trace<" "boss: has the Trace tab"
assert_contains ">Prompts<" "boss: and the Prompts tab"
get "/works/$SLUG?view=trace"
assert_status 200 "boss: the Trace tab opens by direct link"
get "/works/$SLUG?view=prompts"
assert_status 200 "boss: the Prompts tab opens by direct link"

# ================================ more than one draft ================================
new_visitor owner
upload_draft "$D/kettle.md" "The Second Kettle"
SLUG2="$(draft_slug)"
get "/works/$SLUG2"
ev start_read '{}' "/works/$SLUG2"
wait_lacks "/works/$SLUG2" "Reading your draft" 90 "link: the second draft is read"
get "/works/$SLUG?view=read"
assert_contains 'id="linkbox"' "link: the owner of a read draft has the link menu"
assert_contains 'phx-click="toggle_linking"' "link: its button"
ev toggle_linking '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_contains 'phx-click-away="toggle_linking"' "link: open, it closes on a click away"
assert_contains 'phx-click="link_to"' "link: and offers the other draft"
assert_contains "The Second Kettle" "link: by its title"
ID2="$(first_of 'phx-click="link_to" phx-value-id="[0-9]+"' | sed 's/.*phx-value-id="//; s/"//')"
ev link_to '{"id":"'"$ID2"'"}' "/works/$SLUG?view=read"
assert_matches '"redirect":"/links/[0-9]+\?lead='"$SLUG"'"' "link: choosing it goes to the pair"
ev link_to '{"id":"999999"}' "/works/$SLUG?view=read"
assert_matches "That draft can(&#39;|')t be linked." "link: a draft that is not there can't be linked"

# the graph build is a job like the read; the page polls while it runs and stops
ev build_graph '{}' "/works/$SLUG?view=graph"
assert_status 200 "graph: pressing Build answers"
wait_lacks "/works/$SLUG?view=read" "data-poll" 90 "graph: the page stops polling when the build ends"

# the read, started again, throws the old one away
ev start_read '{}' "/works/$SLUG?view=read"
get "/works/$SLUG?view=read"
assert_matches 'Reading your draft|id="read-rail"' "read again: the page shows the new read"
wait_lacks "/works/$SLUG?view=read" "Reading your draft" 90 "read again: and it finishes"
assert_contains "They set the scene at the window" "read again: with the same beats"
