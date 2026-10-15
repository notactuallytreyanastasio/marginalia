#!/usr/bin/env bash
# 70_links.sh: /links (the index, the folder tool, the picker, paging, the filter, the webs) and
# /links/:id, /links/:id/read (the waiting view, the follow view, the tour, the chat bubble).
# Runs only when "70_links.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md part 7 and 6), 58 tests in 7 files:
#   link_index_test (7), links_index_scroll_test (6), link_flow_test (16, the pair page's half),
#   link_chat_flow_test (15), link_tag_menu_test (4), cluster_view_test (4).
#   (snap_view_test belongs to the draft page.)
#
# How the data gets there. The Elixir tests built works, nodes and edges through the contexts. Here
# the people are guests (a visit to /links mints one), and the drafts, their maps and the links
# that are not the point of a test are inserted with sqlite3 straight into MARGINALIA_DB: a read
# of a draft is a different test. What IS driven through the app: making a link from the picker,
# the pass that reads it (a forked job asking fake_llm; test/fixtures/llm/"MANUSCRIPT A.linker.json"
# answers with an edge between nodes 7000001 and 7000003, so the first pair below is the one that
# can be linked), the chat (test/fixtures/llm/"THE PAIR.linkchat.json"), the folder tool
# (the stacks agent's "choose which PAIRS...propose_links.json" answers with the pair 1 and 2 of the
# folder) and all the events.
#
# What this file does not do. The CSS structure test of link_chat_flow_test (an Elixir regex over the
# authored app.css) is skipped: the stylesheet is the compiled one, byte for byte. A first event after a
# hook has run in the browser (Follow, Wiring, Walk, StickDown, LinkChat) is not reachable from curl:
# what is asserted is the markup each of them reads.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

PASS='hello world!'
DB="${MARGINALIA_DB:-}"
if ! command -v sqlite3 >/dev/null 2>&1 || [ -z "$DB" ] || [ ! -f "$DB" ]; then
  skip "links: needs the sqlite3 command and MARGINALIA_DB (the data is inserted with SQL)"
  exit 0
fi

sql() { sqlite3 -cmd '.timeout 8000' "$DB" "$1"; }

# switch JAR: another person's session, with its csrf token fetched (an event needs the token of the session it is sent from)
switch() { JAR="$1"; get /links; }

# a guest of its own: a visit to /links mints one. Sets GUEST_ID, leaves JAR on its jar.
mkguest() { new_visitor "$1"; get /links; GUEST_ID="$(sql "select id from users where is_guest = 1 order by id desc limit 1")"; }

# mkwork USER TITLE STATUS -> WORK_ID (a draft of one section with a paragraph that starts with the
# quote every node below is anchored to)
mkwork() {
  local slug="e2e-$RANDOM$RANDOM$RANDOM" body
  body="# $2

A sentence long enough to be a section. $(words 20)"
  sql "insert into works (user_id, title, body, word_count, status, slug) values ($1, '$2', '$body', 30, '$3', '$slug')"
  WORK_ID="$(sql "select id from works where slug = '$slug'")"
  sql "insert into sections (work_id, ordinal, title, body, word_count) values ($WORK_ID, 1, 'Section 1', '$body', 30)"
}

# mknode WORK ID TITLE [QUOTE]: a beat anchored to the work's first section (spine, no quote: no section)
mknode() {
  if [ -n "${4:-}" ]; then
    sql "insert into nodes (id, work_id, section_id, node_type, title, body, quote, ordinal) values ($2, $1, (select id from sections where work_id = $1 order by ordinal limit 1), 'beat', '$3', 'b', '$4', $2)"
  else
    sql "insert into nodes (id, work_id, node_type, title, body, ordinal) values ($2, $1, 'spine', '$3', 'b', $2)"
  fi
}

# mklink A B STATUS [SUMMARY] -> LINK_ID (lowest work id first)
mklink() {
  local lo="$1" hi="$2"
  [ "$lo" -gt "$hi" ] && { lo="$2"; hi="$1"; }
  sql "insert into links (a_work_id, b_work_id, status, summary) values ($lo, $hi, '$3', $(if [ -n "${4:-}" ]; then echo "'$4'"; else echo NULL; fi))"
  LINK_ID="$(sql "select id from links where a_work_id = $lo and b_work_id = $hi")"
}

# mkedge LINK FROM TO TYPE WHY ORDINAL
mkedge() { sql "insert into link_edges (link_id, from_id, to_id, edge_type, rationale, ordinal) values ($1, $2, $3, '$4', '$5', $6)"; }

# evh NAME PAYLOAD PATH: POST /ev/NAME. BODY_F becomes the decoded #main html of the answer; the raw
# JSON is kept in $EV_JSON. ev_flash / ev_redirect read it.
EV_JSON="$T/ev.json"
evh() {
  ev "$1" "$2" "$3"
  cp "$BODY_F" "$EV_JSON"
  jq -r '.regions["#main"] // ""' "$EV_JSON" > "$BODY_F" 2>/dev/null
}
ev_flash() { jq -r '(.flash.error // .flash.info // "")' "$EV_JSON" 2>/dev/null; }
ev_redirect() { jq -r '.redirect // ""' "$EV_JSON" 2>/dev/null; }
count_in() { grep -o -- "$1" "$BODY_F" | wc -l | tr -d ' '; }

# ============================ the people, the drafts, the maps ===========================
mkguest writer; U1="$GUEST_ID"; JAR_W="$JAR"
mkwork "$U1" "Alpha draft" read;   A="$WORK_ID"; A_SLUG="$(sql "select slug from works where id = $A")"
mkwork "$U1" "Beta draft" read;    B="$WORK_ID"; B_SLUG="$(sql "select slug from works where id = $B")"
mkwork "$U1" "Gamma draft" reading; G="$WORK_ID"
mknode "$A" 7000001 "a beat in Alpha" "A sentence long enough"
mknode "$A" 7000002 "the spine of Alpha"
mknode "$B" 7000003 "a beat in Beta" "A sentence long enough"
mknode "$B" 7000004 "the spine of Beta"

# links of the writer's three drafts (the other files of this suite share the database: never count all of it)
mine() { sql "select count(*) from links where a_work_id in ($A, $B, $G) or b_work_id in ($A, $B, $G)"; }

# ============================ link_index_test ============================
JAR="$JAR_W"
get /links
# test "it offers the drafts that have been read, and says why not the others"
assert_status 200 "index: /links opens"
assert_contains "<h1>Linked drafts</h1>" "index: the page says Linked drafts"
assert_contains "Alpha draft" "index: a read draft is offered (Alpha)"
assert_contains "Beta draft" "index: a read draft is offered (Beta)"
assert_not_contains "Gamma draft" "index: a draft still being read is not offered"
assert_contains "1 draft is still being read." "index: the page says why (still being read)"
assert_contains "Nothing linked yet." "index: nothing is linked yet"
assert_contains "<title" "index: titled"
assert_contains "Linked drafts · Marginalia" "index: the title is Linked drafts"

# test "changing a pick patches the form instead of growing another one"
assert_eq "$(count_in '<select')" "2" "index: two selects on a fresh page"
evh pick "{\"a\":\"$A\",\"b\":\"\"}" /links
assert_eq "$(count_in '<select')" "2" "index: still two selects after picking a"
assert_contains "<option value=\"$A\" selected>" "index: the pick is selected in its own select"
assert_contains "<option value=\"$A\" disabled>" "index: and disabled in the other"
evh pick "{\"a\":\"\",\"b\":\"$A\"}" /links
assert_eq "$(count_in '<select')" "2" "index: still two selects after picking b"

# test "the same draft twice is refused"
evh make "{\"a\":\"$A\",\"b\":\"$A\"}" /links
case "$(ev_flash)" in *"two different drafts"*) _ok "index: the same draft twice is refused with a flash" ;; *) _bad "index: the same draft twice is refused with a flash" "flash: $(ev_flash)" ;; esac
assert_eq "$(mine)" "0" "index: and no link was made"

# test "picking two and linking them starts the pass and goes to the pair"
evh make "{\"a\":\"$A\",\"b\":\"$B\"}" /links
LID="$(sql "select id from links where a_work_id = $A and b_work_id = $B")"
assert_eq "$(ev_redirect)" "/links/$LID" "index: making the link goes to /links/<id>"
assert_eq "$(mine)" "1" "index: the pair was created"
# the pass runs in a forked job against fake_llm; the page fills in by itself
assert_waits "/links/$LID" 'id="follow"' 60 "index: the pass lands and the pair's page becomes the follow view"
assert_eq "$(sql "select status from links where id = $LID")" "linked" "index: the link is linked"
assert_eq "$(sql "select count(*) from link_edges where link_id = $LID")" "1" "index: the one edge between real nodes was kept"

# test "linking the same pair twice reuses the one link"
evh make "{\"a\":\"$B\",\"b\":\"$A\"}" /links
assert_eq "$(ev_redirect)" "/links/$LID" "index: the same pair from the other side is the same link"
assert_eq "$(mine)" "1" "index: still one link"
assert_waits "/links/$LID" 'id="follow"' 60 "index: and it reads again to the same page"

# test "existing pairs are listed with what was found"
get /links
assert_contains "<a href=\"/links/$LID\" class=\"lx-row\">" "index: the pair is a row that goes to it"
assert_contains "Alpha draft <span class=\"x\">↔</span> Beta draft" "index: the row names both drafts"
assert_contains "Beta draft answers Alpha draft, and they part over the kettle." "index: the summary, with the documents called by their names"
assert_contains "<span class=\"n\">1 edges</span>" "index: the edge count"
assert_contains "<span class=\"k tension\">tension 1</span>" "index: the kinds of edge"
assert_contains "1 of 1 linked" "index: the counter"
assert_not_contains "Nothing linked yet." "index: and no longer empty"

# test "a pair still being worked on says so"
mklink "$A" "$G" linking
get /links
assert_contains "<span class=\"st linking\">linking</span>" "index: a pair being worked on says linking"
sql "update links set status = 'failed', error = ':no_edges' where id = $LINK_ID"
get /links
assert_contains "<span class=\"st failed\">failed</span>" "index: a failed pair says failed"
assert_contains "<p class=\"sum err\">:no_edges</p>" "index: and why"
sql "delete from links where id = $LINK_ID"

# test "someone else's links are not listed"
mkguest other; U2="$GUEST_ID"; JAR_O="$JAR"
mkwork "$U2" "Theirs one" read; X="$WORK_ID"
mkwork "$U2" "Theirs two" read; Y="$WORK_ID"
mklink "$X" "$Y" linked "Theirs relate."
get /links
assert_contains "Theirs one" "index: the other writer sees their own link"
assert_not_contains "Alpha draft" "index: and not mine"
switch "$JAR_W"
assert_not_contains "Theirs one" "index: I do not see theirs"
assert_not_contains "Theirs relate." "index: nor their summary"

# a visitor who arrives with nothing is given a guest and an empty page
new_visitor stranger
get /links
assert_status 200 "index: a stranger is let in as a guest"
assert_contains "Nothing linked yet." "index: and sees an empty page"
assert_contains "You need two drafts that have been read." "index: with the reason there is no picker"

# a draft that is someone else's, or not read, is refused at the door
switch "$JAR_W"
evh make "{\"a\":\"$A\",\"b\":\"$X\"}" /links
case "$(ev_flash)" in *"Pick two drafts of yours"*) _ok "index: a draft of someone else's is refused" ;; *) _bad "index: a draft of someone else's is refused" "flash: $(ev_flash)" ;; esac
evh make "{\"a\":\"$A\",\"b\":\"$G\"}" /links
case "$(ev_flash)" in *"Pick two drafts of yours"*) _ok "index: a draft that is not read is refused" ;; *) _bad "index: a draft that is not read is refused" "flash: $(ev_flash)" ;; esac
assert_eq "$(sql "select count(*) from links where a_work_id in ($A, $B, $G, $X, $Y)")" "2" "index: neither made a link (mine and theirs only)"

# ============================ links_index_scroll_test ============================
mkguest scroller; U3="$GUEST_ID"; JAR_S="$JAR"
declare -a SW
for i in 1 2 3 4 5 6 7 8 9 10; do mkwork "$U3" "Draft $i" read; SW[$i]="$WORK_ID"; done
vals=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  for j in 1 2 3 4 5 6 7 8 9 10; do
    [ "$i" -lt "$j" ] && vals="$vals${vals:+,}(${SW[$i]},${SW[$j]},'linked')"
  done
done
sql "insert into links (a_work_id, b_work_id, status) values $vals"
switch "$JAR_S"
# test "it draws a page of rows, not all of them"
assert_eq "$(count_in 'class="lx-row"')" "40" "scroll: forty rows of forty-five"
assert_contains "Show 5 more" "scroll: and the way to more"
assert_contains "of 5 left" "scroll: with how many are left"
# test "the tools and the diagrams are folded, not gone"
assert_contains "<details" "scroll: the diagrams are folded"
assert_matches "[0-9]+ webs? of three or more" "scroll: the webs are counted"
# test "asking for more gives more, and eventually all of them"
evh more '{}' /links
assert_eq "$(count_in 'class="lx-row"')" "45" "scroll: more gives the rest"
assert_not_contains "lx-more" "scroll: and the control goes"
evh more '{}' /links; evh more '{}' /links
assert_eq "$(count_in 'class="lx-row"')" "45" "scroll: asking again breaks nothing"
# test "the filter matches either side of a pair"
evh filter '{"q":"Draft 7"}' /links
n="$(count_in 'class="lx-row"')"
assert_eq "$([ "$n" -gt 0 ] && [ "$n" -lt 45 ] && echo some)" "some" "scroll: the filter keeps the pairs with Draft 7 on either side ($n)"
assert_contains "Draft 7" "scroll: and shows it"
# test "filtering resets the paging, so the count is not a lie"
evh filter '{"q":"draft"}' /links
assert_eq "$(count_in 'class="lx-row"')" "40" "scroll: a new filter starts at one page again"
# test "a filter that matches nothing says so instead of showing everything"
evh filter '{"q":"nonesuch"}' /links
assert_contains "Nothing matches “nonesuch”." "scroll: a filter that matches nothing says so"
assert_eq "$(count_in 'class="lx-row"')" "0" "scroll: and shows no rows"

# ============================ cluster_view_test ============================
# test "three drafts and two links draw as one shape"
mkguest webs; U4="$GUEST_ID"; JAR_C="$JAR"
mkwork "$U4" "Alpha web" read; W1="$WORK_ID"; W1S="$(sql "select slug from works where id = $W1")"
mkwork "$U4" "Beta web" read;  W2="$WORK_ID"
mkwork "$U4" "Gamma web" read; W3="$WORK_ID"
mklink "$W1" "$W2" linked; L12="$LINK_ID"
mklink "$W2" "$W3" linked; L23="$LINK_ID"
get /links
assert_contains "1 web of three or more" "webs: three drafts and two links are one web"
assert_contains "3 drafts, 2 links" "webs: with its size"
assert_contains '<svg class="lx-svg" viewBox="0 0 520 300"' "webs: drawn"
assert_eq "$(count_in 'class="node"')" "3" "webs: three nodes"
# test "a node opens its draft and an edge opens that pair"
assert_contains "<a href=\"/works/$W1S\" class=\"node\">" "webs: a node opens its draft"
assert_contains "<a href=\"/links/$L12\" class=\"edge\">" "webs: an edge opens that pair"
assert_contains "Not related yet:" "webs: the pair nobody has related is drawn as the question it is"
# test "a lone pair is not drawn — there is no shape to show"
switch "$JAR_W"
assert_not_contains "of three or more" "webs: a lone pair is not drawn"
assert_not_contains "<svg" "webs: no diagram for it"
skip "webs: save the rendered page so it can be looked at (a file the Elixir test wrote for a human; nothing to assert)"

# ============================ link_flow_test: the page you land on ============================
mkguest waiter; U5="$GUEST_ID"; JAR_P="$JAR"
mkwork "$U5" "First wait" read;  P1="$WORK_ID"
mkwork "$U5" "Second wait" read; P2="$WORK_ID"
mknode "$P1" 7000101 "a beat in First" "A sentence long enough"
mknode "$P2" 7000103 "a beat in Second" "A sentence long enough"
mklink "$P1" "$P2" pending; PL="$LINK_ID"
# test "says it is working while the pass runs"
get "/links/$PL"
assert_status 200 "waiting: a pending pair has a page"
assert_contains 'id="wiring"' "waiting: both maps and the pairs tried between them"
assert_contains "possible pairs" "waiting: says how many pairs"
assert_contains "The nodes are yours." "waiting: honest that the arcs are attempts, not findings"
assert_not_contains 'id="split"' "waiting: there is no split view"
assert_contains 'data-poll="2"' "waiting: the page polls while it is pending"
assert_contains 'phx-hook="Wiring"' "waiting: the Wiring hook is on the stage"
assert_contains 'data-a="[&quot;a beat in First&quot;]"' "waiting: the dots are the lead's beats"
assert_contains '<circle cx="90" cy="30.0" r="3.5" data-side="a" data-i="0"' "waiting: and are rendered here, not by the hook"
# test "the follow view says so too, and subscribes"
get "/links/$PL/read?lead=$(sql "select slug from works where id = $P1")"
assert_contains 'id="wiring"' "waiting: /read is the same page"
# test "a failure is shown with a way to retry"
sql "update links set status = 'failed', error = ':truncated' where id = $PL"
get "/links/$PL"
assert_contains "did not go through" "waiting: a failure says so"
assert_contains ":truncated" "waiting: with the reason"
assert_contains "Try again" "waiting: and a way to retry"
assert_not_contains 'data-poll' "waiting: and does not poll"
# the pass lands and the page fills in on its own (here by Try again, which starts the pass)
evh relink '{}' "/links/$PL"
assert_contains 'id="wiring"' "waiting: Try again shows the waiting view straight away"
assert_contains 'data-poll="2"' "waiting: and polls"
assert_waits "/links/$PL" 'id="follow"' 60 "waiting: when the pass lands the page fills in without a reload"
get "/links/$PL"
assert_not_contains 'id="wiring"' "waiting: and the waiting view is gone"
assert_not_contains 'data-poll' "waiting: and the polling with it"
# a pass that read nothing fails with the reason
mkguest empty; U6="$GUEST_ID"; JAR_E="$JAR"
mkwork "$U6" "No map one" read; E1="$WORK_ID"
mkwork "$U6" "No map two" read; E2="$WORK_ID"
mklink "$E1" "$E2" pending; EL="$LINK_ID"
get "/links/$EL"
evh relink '{}' "/links/$EL"
assert_waits "/links/$EL" ':not_read' 60 "waiting: a pair with no maps fails with :not_read"
# someone with the address may look, not run
switch "$JAR_O"
evh relink '{}' "/links/$EL"
case "$(ev_flash)" in *"not yours to run"*) _ok "waiting: a stranger cannot make the model read it again" ;; *) _bad "waiting: a stranger cannot make the model read it again" "flash: $(ev_flash)" ;; esac

# test "a link that is not there"
get /links/999999
assert_redirect_to "/works" "link: an unknown id goes to the drafts"
get /links/abc
assert_status 404 "link: an id that is not a number is a 404"

# ============================ link_flow_test: the tour ============================
mkguest tourist; U7="$GUEST_ID"; JAR_T="$JAR"
mkwork "$U7" "First tour" read; T1="$WORK_ID"; T1S="$(sql "select slug from works where id = $T1")"
mkwork "$U7" "Second tour" read; T2="$WORK_ID"; T2S="$(sql "select slug from works where id = $T2")"
mknode "$T1" 7000201 "a beat in First" "A sentence long enough"
mknode "$T2" 7000203 "a beat in Second" "A sentence long enough"
mklink "$T1" "$T2" linked "They talk."; TL="$LINK_ID"
mkedge "$TL" 7000201 7000203 tension "They part." 0
# test "a first visit is told how to work the page"
get "/links/$TL/read"
assert_contains "Two documents, read as one" "tour: a first visit is told how the page works"
assert_contains "The left is what you are reading" "tour: in its own words"
assert_contains 'class="fl-tour-veil" phx-click="dismiss_tour"' "tour: a veil that dismisses"
# test "the bubble is not offered underneath the tour card"
assert_not_contains "lc-bubble" "tour: the chat bubble is under the veil and is not rendered"
# test "it is marked seen on sight, so it does not come back"
case "$(sql "select seen_tours from users where id = $U7")" in *follow*) _ok "tour: the user has seen it" ;; *) _bad "tour: the user has seen it" ;; esac
evh dismiss_tour '{}' "/links/$TL/read"
assert_not_contains "Two documents, read as one" "tour: Got it puts it away"
assert_contains "lc-bubble" "tour: and the bubble appears"
get "/links/$TL/read"
assert_not_contains "Two documents, read as one" "tour: a second visit is not told again"
# test "the ? in the bar brings it back"
evh show_tour '{}' "/links/$TL/read"
assert_contains "Two documents, read as one" "tour: the ? brings it back"
evh dismiss_tour '{}' "/links/$TL/read"

# ============================ link_flow_test: the split view is gone ============================
for path in "/links/$TL" "/links/$TL/read"; do
  get "$path"
  assert_contains 'id="follow"' "split: $path serves the follow view"
  assert_not_contains 'id="split"' "split: and not a split view ($path)"
done
assert_not_contains ">Split<" "split: nothing offers a Split tab any more"

# ============================ the follow view's markup ============================
get "/links/$TL/read?lead=$T1S"
assert_contains '<div class="fl" id="follow" phx-hook="Follow">' "follow: the hook's element"
assert_contains 'id="fl-lead"' "follow: the lead column is addressable"
assert_contains 'id="fl-other"' "follow: and the other, even though a phone does not show it"
assert_contains "<title data-default" "follow: has a title"
assert_contains "First tour · alongside Second tour · Marginalia" "follow: titled by the two drafts"
assert_contains 'content="noindex, nofollow"' "follow: and not for search"
assert_contains '<button class="fl-help" phx-click="show_tour" title="How this page works">?</button>' "follow: the ? in the bar"
assert_contains 'class="fl-swap"' "follow: swap sides"
assert_contains "<a href=\"/links/$TL/read?lead=$T2S\" class=\"fl-swap\"" "follow: swap sides goes to the other lead"
assert_contains 'phx-click="set_only" phx-value-only="tension">tension 1</button>' "follow: the legend offers the relation the pair has"
assert_contains "<span class=\"fl-count\"><b>0</b> / 1 addressed</span>" "follow: the count the hook rewrites"
assert_contains "<span class=\"peek\">They talk.</span>" "follow: the account of the pair"
assert_contains 'id="blk-lead-s1p1"' "follow: the passages the hook needs to reach are addressable (lead)"
assert_contains 'id="blk-other-s1p1"' "follow: (other)"
assert_contains 'data-peer-ref="s1p1"' "follow: each note carries the paragraph it snaps to"
assert_contains 'data-edge="' "follow: and its edge"
assert_contains 'data-why="They part."' "follow: and its reason"
assert_contains 'class="fl-mid"' "follow: the middle"
assert_contains 'class="fl-strip"' "follow: the strip"
assert_contains 'class="fl-sheet"' "follow: the sheet"
assert_contains 'class="far"' "follow: the passage they exist to show"
assert_contains 'class="fl-strip-head"' "follow: a head that says what this is"
assert_contains 'class="rel"' "follow: the relation"
assert_contains 'class="nth"' "follow: and where it is"
assert_contains "ask about this" "follow: the way into the chat, since the drawn line is thin to hit"
assert_eq "$(count_in 'class="shut"')" "1" "follow: exactly one close button on the phone's sheet"
assert_not_contains "cite_current" "follow: no server-owned cite event"
assert_contains '<mark id="anchor-lead-s1p1">A sentence long enough</mark>' "follow: the anchored span is marked, namespaced by side"
# test "the reference can be swapped without leaving the page" / "a draft with one link gets no switcher"
assert_not_contains 'fl-pick' "follow: a draft with one link gets no switcher"
mkwork "$U7" "Third tour" read; T3="$WORK_ID"
mknode "$T3" 7000301 "a beat in Third" "A sentence long enough"
mklink "$T1" "$T3" linked "Third develops First."; TL2="$LINK_ID"
mkedge "$TL2" 7000201 7000301 develops "It carries on." 0
get "/links/$TL?lead=$T1S"
assert_contains '<details class="fl-pick">' "others: the draft lists every one of them"
assert_contains '<span class="t">Second tour</span>' "others: the reference is named"
assert_contains '<span class="t">Third tour</span>' "others: the other is offered"
assert_contains "<a href=\"/links/$TL2?lead=$T1S\" class=\"row\">" "others: and goes to its pair with the same lead"
assert_contains 'Relate it to another…' "others: and to the list"
get "/links/$TL2?lead=$T1S"
assert_contains 'Third develops First.' "others: the other pair has its own account"
assert_not_contains 'They talk.' "others: not the first's"
get "/links/$TL?lead=$T2S"
assert_not_contains 'fl-pick' "others: the second draft, with one link, has no switcher"

# ============================ link_tag_menu_test ============================
mkguest novelist; U8="$GUEST_ID"; JAR_N="$JAR"
mkwork "$U8" "The novel" read; N1="$WORK_ID"
# the story has three paragraphs, each starting with the line a far end is anchored to
body="# The story

The kettle went cold on the counter. $(words 10)

Nobody moved to fill it again. $(words 10)

The window stayed open all night. $(words 10)"
slug="e2e-story-$RANDOM"
sql "insert into works (user_id, title, body, word_count, status, slug) values ($U8, 'The story', '$body', 40, 'read', '$slug')"
N2="$(sql "select id from works where slug = '$slug'")"
sql "insert into sections (work_id, ordinal, title, body, word_count) values ($N2, 1, 'Section 1', '$body', 40)"
sql "update sections set body = '# The novel

He stops in the doorway and does not go through. $(words 10)' where work_id = $N1"
mknode "$N1" 7000401 "Near end 1" "He stops in the doorway"
mknode "$N1" 7000402 "Near end 2" "He stops in the doorway"
mknode "$N1" 7000403 "Near end 3" "He stops in the doorway"
mknode "$N2" 7000411 "Far end 1" "The kettle went cold on the counter"
mknode "$N2" 7000412 "Far end 2" "Nobody moved to fill it again"
mknode "$N2" 7000413 "Far end 3" "The window stayed open all night"
mklink "$N1" "$N2" linked; NL="$LINK_ID"
mkedge "$NL" 7000401 7000411 pays_off "Reason number 1, which the menu has room for." 0
mkedge "$NL" 7000402 7000412 tension "Reason number 2, which the menu has room for." 1
mkedge "$NL" 7000403 7000413 echoes "Reason number 3, which the menu has room for." 2
get "/links/$NL"
# test "the chip still counts them"
assert_contains "3 links" "tag menu: the chip counts them"
# test "one entry per edge, not one for the first"
for i in 1 2 3; do
  assert_contains "Far end $i" "tag menu: the menu names far end $i"
  assert_contains "Reason number $i, which the menu has room for." "tag menu: and gives its reason ($i)"
done
assert_eq "$([ "$(count_in 'class="fl-jump k-')" -ge 3 ] && echo yes)" "yes" "tag menu: three buttons under the one paragraph"
# test "each entry carries the paragraph it snaps to"
refs="$(grep -o 'data-peer-ref="[^"]*"' "$BODY_F" | sort -u | tr '\n' ' ')"
assert_eq "$refs" 'data-peer-ref="s1p1" data-peer-ref="s1p2" data-peer-ref="s1p3" ' "tag menu: the three far ends are three different paragraphs"
# test "the relation of each entry is its own, not the paragraph's"
for kind in pays_off tension echoes; do assert_contains "fl-jump k-$kind" "tag menu: the entry for $kind is coloured as itself"; done
assert_contains "fl-tagwrap mixed" "tag menu: a chip whose edges disagree says so"
# the relation filter: one kind at a time
evh set_only '{"only":"tension"}' "/links/$NL"
assert_contains 'phx-value-only="tension">tension 1</button>' "tag menu: the legend offers it"
assert_contains 'class="mg-tab on" phx-click="set_only" phx-value-only="tension"' "tag menu: and shows which is chosen"
assert_not_contains "k-pays_off" "tag menu: the other kinds leave the page"
evh set_only '{"only":"all"}' "/links/$NL"
assert_contains "k-pays_off" "tag menu: everything again"

# ============================ link_chat_flow_test ============================
switch "$JAR_W"
LP="/links/$LID/read"
get "$LP"
# (the writer has had the card already: the bubble is there)
# test "the bubble is on the page and opens the panel"
assert_contains 'phx-click="toggle_chat"' "chat: the bubble is on the page"
assert_not_contains 'class="lc-panel"' "chat: shut"
evh toggle_chat '{}' "$LP"
assert_contains 'class="lc-panel"' "chat: opens the panel"
assert_contains 'phx-submit="chat_send"' "chat: with a form that asks"
assert_contains 'phx-hook="LinkChatComposer"' "chat: whose box is the composer"
assert_contains 'phx-hook="StickDown"' "chat: and whose body sticks down"
# test "an empty chat offers questions rather than a blank box"
assert_contains 'class="lc-openers"' "chat: an empty chat offers questions"
assert_contains "What does the second document already answer?" "chat: the first opener"
# test "asking shows the question and that it is thinking" / the answer
calls0="$(llm_calls)"
evh chat_send '{"message":"What is the disagreement?"}' "$LP"
assert_contains "What is the disagreement?" "chat: the question is shown"
assert_contains "They part over the kettle." "chat: and the reader's answer"
assert_contains "<strong>canned</strong>" "chat: which is markdown"
assert_not_contains "lc-thinking" "chat: and nothing claims to be thinking"
assert_eq "$(( $(llm_calls) - calls0 ))" "1" "chat: one model call"
assert_llm_log_contains "THE PAIR.linkchat.json" "chat: the model was asked with both maps (the card)"
# test "tapping one asks it"  (openers go away once the conversation has started)
assert_not_contains 'class="lc-openers"' "chat: the openers go away once it has started"
# test "a failed answer says so rather than vanishing"
evh chat_send '{"message":"anything FAKE_LLM_500"}' "$LP"
case "$(ev_flash)" in *"That did not go through"*) _ok "chat: a failed answer says so" ;; *) _bad "chat: a failed answer says so" "flash: $(ev_flash)" ;; esac
assert_contains "anything FAKE_LLM_500" "chat: and the question is still shown"
assert_not_contains "lc-thinking" "chat: and it is not still claiming to be thinking"
# test "citing an edge puts that connection into the chat and opens it"
EDGE="$(sql "select id from link_edges where link_id = $LID limit 1")"
evh toggle_chat '{}' "$LP"
assert_not_contains 'class="lc-panel"' "chat: the panel closes again"
evh cite_edge "{\"edge\":\"$EDGE\"}" "$LP"
assert_contains 'class="lc-panel"' "chat: citing opens the chat"
assert_contains 'class="chip tension"' "chat: with the connection as a chip"
assert_contains "a beat in Alpha ↔ a beat in Beta" "chat: naming both ends"
assert_contains "Alpha draft and Beta draft part here." "chat: and its reason is on the page, the drafts called by their names"
assert_contains "phx-click=\"uncite\" phx-value-edge=\"$EDGE\"" "chat: and the chip can be taken out"
evh uncite "{\"edge\":\"$EDGE\"}" "$LP"
assert_not_contains 'class="chip' "chat: the x takes it out of the question"
# test "it offers a way into the chat, and no longer a x that did nothing"
get "$LP"
assert_not_contains 'class="lc-panel"' "chat: a fresh visit starts a fresh chat"
assert_not_contains "What is the disagreement?" "chat: and does not remember the last one"
# someone with the address may look, not ask
switch "$JAR_O"
evh chat_send '{"message":"hello"}' "$LP"
case "$(ev_flash)" in *"not yours to run"*) _ok "chat: someone who owns neither draft may not spend the model's credit" ;; *) _bad "chat: someone who owns neither draft may not spend the model's credit" "flash: $(ev_flash)" ;; esac
switch "$JAR_W"
skip "chat: its head and button are not stranded in the phone's media query (an Elixir regex over the authored app.css; the stylesheet here is the compiled one, byte for byte)"
skip "chat: the hooks (LinkChat, StickDown, Follow, Wiring, Walk) run in the browser; what they read is asserted above"

# ============================ the walkthrough ============================
get "$LP?lead=$A_SLUG&walk=1"
assert_contains 'id="walk" phx-hook="Walk"' "walk: ?walk=1 starts the walkthrough"
assert_contains "&quot;id&quot;:&quot;sides&quot;" "walk: its steps are the page's"
assert_not_contains "fl-tour-veil" "walk: and the card stays away"
evh end_walk '{}' "$LP?lead=$A_SLUG&walk=1"
assert_not_contains 'id="walk"' "walk: ending it takes the overlay away"

# ============================ the folder tool ============================
mkguest folderer; U9="$GUEST_ID"; JAR_F="$JAR"
mkwork "$U9" "Opinion" read; F1="$WORK_ID"
mkwork "$U9" "Dissent" read; F2="$WORK_ID"
mknode "$F1" 7000501 "a beat in Opinion" "A sentence long enough"
mknode "$F2" 7000503 "a beat in Dissent" "A sentence long enough"
sql "insert into folders (name, user_id) values ('Case file', $U9)"
FOLDER="$(sql "select id from folders where user_id = $U9 limit 1")"
sql "update works set folder_id = $FOLDER where id in ($F1, $F2)"
get /links
assert_contains "relate a whole folder" "folder: the tool is there, folded"
assert_contains '<select name="folder">' "folder: with the folders"
assert_contains "Work out what to relate" "folder: and its button"
evh bulk_propose "{\"folder\":\"$FOLDER\"}" /links
assert_contains 'data-poll="2"' "folder: while the pass runs the page polls"
assert_contains "Reading the folder…" "folder: and says so"
# (the proposal is the stacks agent's "choose which PAIRS...propose_links.json": the pair 1 and 2)
assert_waits /links "Both turn on the same window." 60 "folder: the triage lands and shows the pair it chose"
assert_contains "<span class=\"n\">The second answers the first.</span>" "folder: with the relation it expects"
assert_contains "<strong>Opinion</strong>" "folder: and the drafts, by title"
assert_not_contains "Left out:" "folder: nothing left out is not mentioned"
assert_contains "Relate these 1" "folder: with the way to relate them"
assert_contains 'data-confirm="Read each of these pairs against each other?' "folder: asking first"
assert_not_contains 'data-poll' "folder: and the page stops polling"
evh bulk_relate '{}' /links
assert_contains 'data-poll="2"' "folder: relating runs away from the request and the page polls"
assert_waits /links "Started 1 readings." 90 "folder: and says how many were started"
assert_eq "$(sql "select status from links where a_work_id = $F1 and b_work_id = $F2")" "linked" "folder: the pair was read"
evh bulk_propose '{"folder":"oops"}' /links
assert_not_contains "Reading the folder…" "folder: an id that is not a number does nothing"
evh bulk_propose '{"folder":"999999"}' /links
assert_waits /links "Could not read that folder: :no_folder" 60 "folder: a folder that is not yours is :no_folder"
