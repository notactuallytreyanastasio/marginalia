#!/usr/bin/env bash
# 40_cases.sh: the landing page, /cases, /cases/:slug, /cases/:slug/read[/:lead], their tour,
# their chat, their Open Graph tags. Runs only when "40_cases.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md): landing_live_test (14), landing_features_test (34, the half that
# can be seen from outside: the source-reading half is a named skip), case_index_test (22),
# case_page_test (8), case_read_test (22), cases_tour_test (12), og_test (6).
#
# The Elixir tests built their data with Works.create_work, Cases.place and Links.store_edges.
# Here the owner registers through /users/register, as a person would, and the documents, nodes,
# links and edges are inserted with sqlite3 into the app's own database (MARGINALIA_DB), because
# producing an anchored read by hand is what the read pipeline is for and not what these pages
# are about. The ids are in the 9000s so nothing another file uploads can collide with them.
#
# The owner is whoever accountsOwnerEmail() says: OWNER_EMAIL, default bobbbygrayson@gmail.com.
# (e2e.sh exports MARGINALIA_OWNER_EMAIL, which the accounts library does not read.)
#
# What the LiveView tests could do that curl cannot: click a button by selector (done here by
# sending the event the button's phx-click names, with the phx-value-* it carries), and see a
# redirect as {:live_redirect} (here the JSON {"redirect": ...} an event answers with).
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

. "$(dirname "$0")/../cases_fixtures.sh"

if ! command -v sqlite3 >/dev/null 2>&1 || [ -z "${MARGINALIA_DB:-}" ]; then
  skip "cases: no sqlite3 or no MARGINALIA_DB, the fixtures cannot be placed"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# The owner, and the fixtures (the helpers are in blimp/test/cases_fixtures.sh)
# ---------------------------------------------------------------------------------------------
new_visitor setup
cases_owner

# ---- Trump v. Slaughter (case_index_test): the index alone, so the lede counts one case
mkdoc 9101 s1op "Trump v. Slaughter — Opinion of the Court" "Trump v. Slaughter" opinion 1 \
  "A majority opinion that announces its destination in section one." \
  "https://www.supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf"
mkdoc 9102 s1di "Trump v. Slaughter — Dissent (Sotomayor)" "Trump v. Slaughter" dissent 1
mkdoc 9103 s1ar "Trump v. Slaughter — Argument: Gen. D. John Sauer" "Trump v. Slaughter" argument 1
mklink 9101 9101 9102 tension "The Court grounds removal in the Framers'' single executive; the dissent finds no founding-era support for it." "They disagree about removal." 9101
mklink 9102 9101 9103 echoes "Sauer''s framing." "Adopted from the lectern." 9102

# ============================================================================================
# og_test, cases_tour_test: the front page and the index, before anything else is on them
# ============================================================================================
new_visitor visitor
USERS_BEFORE="$(db_count users)"

get /
assert_status 200 "landing: / is 200"
assert_eq "$(meta_content og:image | sed 's#.*/images#/images#')" "/images/og.png" "og: the front page keeps the product's own card"
OGURL="$(meta_content og:url)"
case "$OGURL" in */) _ok "og: the front page's og:url ends with a slash" ;; *) _bad "og: the front page's og:url ends with a slash" "og:url = $OGURL" ;; esac

get /cases
assert_status 200 "cases: /cases is 200"
assert_eq "$(meta_content og:title)" "The term, read closely" "og: /cases has its own title"
assert_contains "og-cases.png" "og: /cases names its own card"
assert_eq "$(meta_content og:image | sed 's#.*/images#/images#')" "/images/og-cases.png" "og: og:image is the cases card"
assert_eq "$(meta_content twitter:image | sed 's#.*/images#/images#')" "/images/og-cases.png" "og: twitter:image is the cases card"
case "$(meta_content og:image:alt)" in *"dissent arguing with that exact sentence"*) _ok "og: the card's alt text describes it" ;; *) _bad "og: the card's alt text describes it" "alt = $(meta_content og:image:alt)" ;; esac
case "$(meta_content og:description)" in *"1 Supreme Court cases, 3 documents"*) _ok "og: the description counts the corpus rather than describing it" ;; *) _bad "og: the description counts the corpus" "desc = $(meta_content og:description)" ;; esac
case "$(meta_content og:description)" in *"anchored to a sentence in both"*) _ok "og: the description says the connections are anchored in both" ;; *) _bad "og: the description says anchored in both" ;; esac
case "$(meta_content og:url)" in */cases) _ok "og: /cases declares itself, not the site root" ;; *) _bad "og: /cases declares itself" "og:url = $(meta_content og:url)" ;; esac

# ---- case_index_test
# test "the record facts a reader checks first are on the card"
assert_contains "No. 25-332" "index: the docket"
assert_contains "Argued December 8, 2025" "index: when it was argued"
assert_contains "Decided June 29, 2026" "index: when it was decided"
assert_contains "question presented" "index: the question presented"
assert_contains "Humphrey&#39;s Executor" "index: the question names Humphrey's Executor"
# describe "the holding"
assert_contains "the Court, holding" "index: the holding is quoted"
assert_contains "We hold that the removal power is the President&#39;s alone." "index: it is the Court's own sentence, lifted from the opinion"
assert_contains "constitutes no part of the" "index: the page says the syllabus is no part of the opinion"
assert_contains "The Reporter's syllabus is excluded" "index: the page says the syllabus is not a source"
assert_not_contains "what the Court held" "index: nothing says 'what the Court held' any more"
# test "the read pass's own account of the opinion is shown, and expands"
assert_contains "on reading the opinion" "index: the read pass's account of the opinion is shown"
assert_contains "announces its destination in section one" "index: it is the opinion's first impression"
assert_contains "fi clamped" "index: clamped until asked"
assert_contains "phx-value-slug=\"trump-v-slaughter\"" "index: the more button names the case"
# test "every document is named and carries its source"
assert_contains "Argument: Gen. D. John Sauer" "index: the advocate is named, not 'Oral argument' three times over"
assert_contains "Opinion of the Court" "index: the opinion is the Opinion of the Court"
assert_contains "supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf" "index: the PDF each document was made from"
assert_contains "/cases/trump-v-slaughter/read/s1ar" "index: each document opens the case read on that document"
# test "the card offers pairings, which are how a case is actually read"
assert_contains 'class="cs-ways"' "index: the card offers pairings"
assert_contains "against" "index: one document against another"
assert_matches 'href="/links/[0-9]+\?lead=' "index: the pairing lands in the reading where the second follows the first"
assert_matches 'class="a opinion"[^>]*>[[:space:]]*Opinion of the Court' "index: the opinion leads the pair, not the dissent"
assert_contains "or all 3 at once →" "index: the whole-case read is the quiet alternative"
assert_contains "connections →" "index: and so is the connections page"
# test "the hook is a real disagreement, before any explanation"
assert_contains 'class="cs-hook"' "index: there is a hook"
assert_contains "no founding-era support" "index: it is a real disagreement"
assert_contains '<details class="cs-how"' "index: the method is folded, and below"
# test "one case is one case, not 1 cases"
assert_contains "</b> case</span>" "index: one case is a case"
assert_not_contains "</b> cases</span>" "index: and not 1 cases"
assert_contains "1 case from the Supreme Court" "index: the lede counts one case"
# test "the lede counts the cases it is actually showing"
assert_not_contains "Four cases" "index: the lede is not a stale number"
assert_contains "2025 term" "index: the year comes off the decision dates of the cases on the page"
# test "it opens with one real connection, not a description of one"
assert_contains "for instance" "index: it opens with a connection"
assert_contains "read it →" "index: and a way into it"
# test "the provenance note says what this is and is not"
assert_contains "Supreme Court of the United States" "index: the provenance names the source"
assert_contains "verified against the source" "index: it says every quote is verified"
assert_contains "a substitute for reading the opinion" "index: it says what it is not"
# test "a visitor who is not the owner sees all of it"
assert_contains "The term, read closely" "index: a visitor sees the page"
assert_contains "No. 25-332" "index: and the record"

# ---- cases_tour_test: the index carries the tour
assert_contains 'id="walk"' "tour: the page always carries the tour"
assert_contains 'data-auto="cases"' "tour: and says to gate it locally"
assert_contains "One real disagreement, first" "tour: its first step is on the page"
assert_contains "Take the tour" "tour: the button is there"
assert_contains "mg:walk" "tour: the button asks the overlay directly, with no round trip"
assert_not_contains 'phx-click="start_walk"' "tour: there is no server event to start it"
assert_not_contains 'phx-click="end_walk"' "tour: nor to end it"
assert_contains "Log in" "tour: a signed-out visitor is offered Log in"
assert_not_contains ">guest<" "tour: and is not told they are a guest"
new_visitor visitor2
get /cases
assert_contains "One real disagreement, first" "tour: a different new visitor gets it too, per person not per site"
assert_eq "$(db_count users)" "$USERS_BEFORE" "tour: no account is created to remember it"
get /cases/trump-v-slaughter
assert_eq "$(db_count users)" "$USERS_BEFORE" "tour: nor by the case page"

# ---- the index's two events
new_visitor visitor3
get /cases
evm impression '{"slug":"trump-v-slaughter"}' /cases
assert_not_contains "fi clamped" "index: more unclamps the account of the opinion"
assert_contains ">less</button>" "index: and the button says less"
evm impression '{"slug":"trump-v-slaughter"}' /cases
assert_contains "fi clamped" "index: less clamps it again"
get /cases
assert_contains "fi clamped" "index: a plain visit starts with every clamp shut"
evm walk_hop '{"to":"first_pair"}' /cases
case "$REDIRECT" in /links/*"?lead=s1op&walk=1") _ok "tour: the last step opens the strongest pairing of the first case with ?walk=1" ;; *) _bad "tour: the hop redirects to the pairwise reading" "redirect = '$REDIRECT'" ;; esac
ev walk_hop '{"to":"elsewhere"}' /cases
assert_status 500 "tour: a hop it does not know is a bug in the caller and stops"
get /cases

# test "a collection with no public record still renders" and the index of two cases
mkdoc 9120 loose "Loose ends" "Not a court case" opinion 0
get /cases
assert_contains "Not a court case" "index: a collection with no public record still renders"
assert_contains "2 cases from the Supreme Court" "index: and the lede counts both"
sql "DELETE FROM works WHERE id = 9120"
get /cases
assert_not_contains "Not a court case" "index: and is gone when it is taken out"

# ---- a summary with A and B: the page shows the raw reason (kept as is), the case page shows names
# (case_index_test's three Links.summary tests are the links library's, in Temper)
skip "index: Links.summary resolves 'Manuscript A' / a bare A at the start of a sentence / leaves 'Part A' alone (a links library function; tested in blimp/temper/links)"

# ============================================================================================
# "Some v. Case" (case_page_test, case_read_test), and "Other v. Matter" to relate it to
# ============================================================================================
cases_some_v_case

# ---- case_page_test
new_visitor reader
get /cases/some-v-case
assert_status 200 "case: /cases/some-v-case is 200 for a visitor"
assert_contains "Some v. Case" "case: it renders at all, with no filters set"
assert_contains "They part on consent." "case: and shows the connections"
assert_not_contains ">clear<" "case: the clear button only appears once something is filtered"
assert_contains "or one against another" "case: the fast track into a referential read is on the page"
assert_contains "Opinion ↔ Dissent" "case: the label is the document's own name"
assert_contains "lead=s2op" "case: and it leads with the opinion"
assert_contains "3 documents · " "case: the tally counts the documents"
assert_contains "3 connections" "case: and the connections"
assert_contains "1 connections" "case: each way in says how many it has (1 connections, as the page always read)"
assert_contains 'href="/cases/some-v-case/read"' "case: the whole-case read comes before the pairs"
assert_contains "with 2 other documents in the margin" "case: and says how many documents are in its margin"
assert_contains 'class="doc opinion"' "case: the documents are listed with their roles"
assert_contains 'href="/works/s2op"' "case: Read it → goes to the draft"
assert_contains "hide the documents" "case: the documents can be folded away"
# test "each document is named by what distinguishes it"
mkdoc 9204 s2ar2 "Some v. Case — Argument: Amit Agarwal" "Some v. Case" argument 0
get /cases/some-v-case
assert_contains "Argument: Amit Agarwal" "case: an advocate is named"
assert_contains "Argument: Counsel" "case: and so is the other"
assert_not_contains ">Oral argument<" "case: nobody is 'Oral argument'"
sql "DELETE FROM works WHERE id = 9204"
# test "the way in is in the nav for everyone, signed in or not"
get /cases
assert_contains 'href="/cases"' "case: the way in is in the nav for a signed-out visitor"
new_visitor member
ensure_user "$(new_email)" "$PASS"
get /cases
assert_contains 'href="/cases"' "case: and for a signed-in one"
new_visitor reader
get /cases/some-v-case
# the og tags of the page
assert_eq "$(meta_content og:title)" "Some v. Case" "og: the case page's title is the case's name"
case "$(meta_content og:url)" in */cases/some-v-case) _ok "og: the case page declares itself, not the site root" ;; *) _bad "og: the case page declares itself" "og:url = $(meta_content og:url)" ;; esac
CANON="$(sed -n 's/.*<link rel="canonical" href="\([^"]*\)".*/\1/p' "$BODY_F" | head -1)"
assert_eq "$CANON" "$(meta_content og:url)" "og: the canonical link agrees with og:url"

# the events
evm search '{"q":"consent","_target":["q"]}' /cases/some-v-case
assert_contains "They part on consent." "case: searching keeps the matching connection"
assert_not_contains "It replies" "case: (nothing else of this case is in the fixture)"
assert_not_contains "The lectern already settled this." "case: searching narrows the connections"
assert_contains ">clear<" "case: and offers to clear"
evm clear '{}' /cases/some-v-case
assert_contains "The lectern already settled this." "case: clearing brings them back"
evm search '{"q":"zzzzz"}' /cases/some-v-case
assert_contains "Nothing matches that" "case: a search matching nothing says so"
evm clear '{}' /cases/some-v-case
evm kind '{"k":"tension"}' /cases/some-v-case
assert_contains "They part on consent." "case: slicing by relation keeps the tension"
assert_not_contains "The lectern already settled this." "case: and drops the rest"
evm kind '{"k":"tension"}' /cases/some-v-case
assert_contains "The lectern already settled this." "case: and toggling it off brings them back"
evm pair '{"p":"dissent+opinion"}' /cases/some-v-case
assert_contains "They part on consent." "case: slicing by the kinds of document keeps that pair"
assert_not_contains "Dissent and counsel agree here." "case: and drops the others"
evm clear '{}' /cases/some-v-case
evm open "{\"id\":\"$EDGE_TENSION\"}" /cases/some-v-case
assert_contains 'class="both"' "case: a connection opens to its two passages"
assert_contains "<blockquote>A sentence long enough</blockquote>" "case: the passages are quoted"
assert_contains "Read these two side by side →" "case: and the way into the pair"
evm open "{\"id\":\"$EDGE_TENSION\"}" /cases/some-v-case
assert_not_contains 'class="both"' "case: it shuts again"
evm toggle_docs '{}' /cases/some-v-case
assert_not_contains 'class="cs-docs"' "case: the documents fold away"
assert_contains "show the documents" "case: and the button says so"
evm toggle_docs '{}' /cases/some-v-case
assert_contains 'class="cs-docs"' "case: and come back"
get /cases/some-v-case
assert_not_contains ">clear<" "case: a plain visit starts with no filters"

# an unknown case sends you to the list, with a flash
get /cases/nope
assert_redirect_to "/cases" "case: an unknown case redirects to the list"
get /cases
assert_contains "No such case." "case: with the flash"
get /cases/nope/read
assert_redirect_to "/cases" "case read: an unknown case sends you back to the list"
get /cases/nope/read/whatever
assert_redirect_to "/cases" "case read: whatever the lead"

# ---- case_read_test
new_visitor reader2
get /cases/some-v-case/read
assert_status 200 "case read: /cases/some-v-case/read is 200 for a visitor"
assert_contains "Reading…" "case read: the page says whose view it is"
assert_contains "Some v. Case — Opinion" "case read: the opinion is the default lead"
assert_contains "They part on consent." "case read: the first reason is in the margin"
assert_contains "The lectern already settled this." "case read: and the second, from a separate link, on the same page"
assert_not_contains "Dissent and counsel agree here." "case read: not the link between the other two, which the opinion is not in"
assert_contains '<span class="src">Dissent</span>' "case read: each note says which document it came from, without the case name"
assert_contains '<span class="src">Argument: Counsel</span>' "case read: including the advocate"
assert_contains "<blockquote>A sentence long enough</blockquote>" "case read: the far passage travels with the note"
assert_contains 'class="cr-note s2"' "case read: the dissent's colour class"
assert_contains 'class="cr-note s3"' "case read: the argument's"
assert_contains "<main id=\"main\" class=\"\">" "case read: the bleed layout"
assert_contains '<div class="cr-grid">' "case read: the grid"
assert_contains 'class="cr-text linked" id="b-s1p0"' "case read: the anchored paragraph is a linked row"
assert_contains '<mark id="anchor-s1p0">A sentence long enough</mark>' "case read: and its anchor is highlighted"
assert_contains 'class="cr-notes bare"' "case read: a paragraph nothing touches has a bare margin"
assert_contains '<details class="cr-pick">' "case read: the document picker"
assert_contains 'href="/cases/some-v-case/read/s2ar"' "case read: any document of the case is a link to read it"
assert_contains "Against…" "case read: who is speaking"
assert_contains 'phx-value-w="9203"' "case read: a chip for the dissent"
assert_contains 'phx-value-w="9201"' "case read: and for the advocate"
assert_contains 'phx-value-k="answers"' "case read: a chip for each relation"
assert_not_contains "cr-clear" "case read: nothing to clear yet"
assert_not_contains 'id="walk"' "case read: a plain visit runs no tour"
# the phone's margin
assert_contains 'class="cr-rail"' "case read: every linked paragraph carries a rail"
assert_contains '<span class="tick k-tension">' "case read: with the tension on it"
assert_contains '<span class="tick k-answers">' "case read: and the answer"
assert_contains "connections on this paragraph" "case read: the rail says what it holds"
assert_contains 'phx-value-ref="s1p0"' "case read: and names the paragraph"
# filters
evm source '{"w":"9203"}' /cases/some-v-case/read
assert_contains "They part on consent." "case read: a source chip narrows the margin to one document"
assert_not_contains "The lectern already settled this." "case read: and only that one"
assert_contains "cr-clear" "case read: a clear button appears"
assert_contains "cr-chip s2 on" "case read: and the chip is on"
evm clear '{}' /cases/some-v-case/read
assert_contains "The lectern already settled this." "case read: clear brings the margin back"
evm only '{"k":"answers"}' /cases/some-v-case/read
assert_contains "The lectern already settled this." "case read: a relation chip narrows the margin to one kind"
assert_not_contains "They part on consent." "case read: and only that kind"
evm only '{"k":"answers"}' /cases/some-v-case/read
assert_contains "They part on consent." "case read: the same chip again lets go"
evm clear '{}' /cases/some-v-case/read
# the sheet
evm peek '{"ref":"s1p0"}' /cases/some-v-case/read
assert_contains 'class="cr-sheet"' "case read: tapping the rail opens that paragraph's notes"
assert_contains "on this paragraph" "case read: the sheet says what it holds"
assert_contains "They part on consent." "case read: and the notes are in it"
evm unpeek '{}' /cases/some-v-case/read
assert_not_contains 'class="cr-sheet"' "case read: closing dismisses the sheet"
evm source '{"w":"9203"}' /cases/some-v-case/read
evm peek '{"ref":"s1p0"}' /cases/some-v-case/read
assert_contains "The lectern already settled this." "case read: the sheet holds every note, not only the filtered ones"
evm clear '{}' /cases/some-v-case/read
assert_not_contains 'class="cr-sheet"' "case read: a filter change dismisses a sheet that may no longer apply"
# another lead
get /cases/some-v-case/read/s2ar
assert_contains "Some v. Case — Argument: Counsel" "case read: any document in the case can be the one you read"
assert_contains "The lectern already settled this." "case read: from the argument's side it sees its link with the opinion"
assert_contains "Dissent and counsel agree here." "case read: and its link with the dissent"
assert_not_contains "They part on consent." "case read: and not the link it is not in"
get /cases/some-v-case/read/no-such-document
assert_status 200 "case read: an unknown lead is not a 404"
assert_contains "Some v. Case — Opinion" "case read: it is the default lead"
# meta
get /cases/some-v-case/read
case "$(meta_content og:url)" in */cases/some-v-case/read/s2op) _ok "og: the read page declares its own address" ;; *) _bad "og: the read page declares its own address" "og:url = $(meta_content og:url)" ;; esac
assert_contains "read against the case" "case read: the title says what it is"
assert_contains "read with 2 other documents from Some v. Case in the margin" "case read: the description counts the margin"
# the case page offers it first
get /cases/some-v-case
assert_contains "/cases/some-v-case/read" "case read: the case page offers the whole-case read before the pairs"

# ---- the chat about the case
new_visitor chatter
get /cases/some-v-case/read
assert_contains "lc-bubble" "chat: the bubble is there"
assert_not_contains "lc-panel" "chat: and the panel is shut"
assert_contains 'id="linkchat"' "chat: the hook has its element"
evm toggle_chat '{}' /cases/some-v-case/read
assert_contains "lc-panel" "chat: the bubble opens a panel"
assert_contains "About this case" "chat: about the case"
assert_not_contains "About this pair" "chat: not a pair"
assert_contains 'phx-submit="chat_send"' "chat: with a form that asks"
assert_contains 'phx-hook="LinkChatComposer"' "chat: whose composer is the hook that sends on Enter"
assert_contains 'class="lc-hint"' "chat: an empty conversation shows the hint"
assert_contains "What did the dissent already answer?" "chat: and the openers"
evm close_chat '{}' /cases/some-v-case/read
assert_status 200 "chat: close_chat (Escape) is an answer, not a crash"
assert_not_contains "lc-panel" "chat: it shuts the panel"
evm toggle_chat '{}' /cases/some-v-case/read
evm cite_edge "{\"edge\":\"$EDGE_TENSION\"}" /cases/some-v-case/read
assert_contains "lc-panel" "chat: a note carries its connection into the chat, opening the panel"
assert_contains "lc-cited" "chat: where it is cited"
assert_contains "a beat in the opinion ↔ a beat in the dissent" "chat: by the two passages' titles"
assert_contains 'phx-click="uncite"' "chat: and can be taken out"
evm uncite "{\"edge\":\"$EDGE_TENSION\"}" /cases/some-v-case/read
assert_not_contains "lc-cited" "chat: uncite removes it"
LLM_BEFORE="$(llm_calls)"
evm chat_send '{"message":"   "}' /cases/some-v-case/read
assert_eq "$(( $(llm_calls) - LLM_BEFORE ))" "0" "chat: an empty question asks nothing"
assert_contains 'class="lc-hint"' "chat: and the conversation is still empty"
# Asking calls the model, and 60_cuts.sh counts the fake's requests from zero, so the asks that
# reach the model are in 90_cases_chat.sh, which runs after it.

# ---- the walk (cases_tour_test)
new_visitor walker
get "/cases/some-v-case/read/s2op?walk=1"
assert_contains 'id="walk"' "tour: arriving with walk=1 starts the last leg"
assert_contains "The whole case in one margin" "tour: with its first step"
assert_not_contains 'data-auto' "tour: gated by the server here, not by the browser"
evm end_walk '{}' "/cases/some-v-case/read/s2op?walk=1"
assert_not_contains 'id="walk"' "tour: end_walk removes the overlay"
get /cases/some-v-case/read/s2op
assert_not_contains 'id="walk"' "tour: a plain visit runs no tour"
evm start_walk '{}' /cases/some-v-case/read/s2op
assert_contains "The whole case in one margin" "tour: start_walk starts it"
evm walk_hop '{"to":"case_read"}' /cases/some-v-case/read/s2op
assert_not_contains 'id="walk"' "tour: a hop here just ends it"
skip "tour: the pairwise leg (/links/:id/read?lead=..&walk=1) shows 'Left is read. Right is the reference' and hops to /cases/some-v-case/read/<lead>?walk=1 (the links page, not this group)"

# ---- a case related to another case
mkdoc 9301 farop "Other v. Matter — Opinion" "Other v. Matter" opinion 0
mklink 9301 9202 9301 echoes "The same Court on the same clause, three weeks apart." "Two cases, one question." 9301
new_visitor far
get /cases/some-v-case/read
assert_contains "The same Court on the same clause" "far: its notes appear in the margin"
assert_contains '<p class="from">Other v. Matter</p>' "far: saying where they are from"
assert_contains "cr-note s0 far" "far: and visibly not from this case"
# the markup puts the chip's text on the next line, as the HEEx did: match across lines
if tr '\n' ' ' < "$BODY_F" | grep -qE 'cr-chip[^"]*far[^>]*>[[:space:]]*<span class="t">Other v. Matter'; then
  _ok "far: the chip for another case names the case, not the document"
else
  _bad "far: the chip for another case names the case, not the document" "no far chip naming Other v. Matter"
fi
evm source '{"w":"9203"}' /cases/some-v-case/read
assert_not_contains "The same Court on the same clause" "far: filtering to this case's own documents leaves it out"
evm clear '{}' /cases/some-v-case/read
get /cases
assert_contains "elsewhere in the term" "index: the term argues with itself"
assert_contains "Other v. Matter" "index: the other case is named"
assert_contains "3 cases from the Supreme Court" "index: three cases now"

# ============================================================================================
# landing_live_test, landing_features_test
# ============================================================================================
new_visitor lander
USERS_BEFORE="$(db_count users)"
get /
assert_status 200 "landing: / answers"
# test "renders the pitch and the promise"
assert_contains "Someone who has actually read the whole thing" "landing: the pitch"
assert_contains "what a reader leaves in the margin" "landing: the definition"
assert_contains "It reads. You decide." "landing: the promise"
# test "the page describes the surfaces the product actually has"
for s in "The page, with its notes in the margin" "A thread on one paragraph" "What leads to what" "The one place it writes" "Then you change it yourself" "a hairline appears in the" "drawn to scale" "Connections" "Tensions"; do
  assert_contains "$s" "landing: describes '$s'"
done
# test "it does not promise it will never write, now that it sometimes does"
assert_not_contains "It never writes a word of your book" "landing: no blanket promise never to write"
assert_contains "This is the only" "landing: the narrow, true one"
assert_contains "It never applies anything" "landing: nothing is applied"
assert_contains "No prose you did not ask for" "landing: no unasked prose"
# test "the privacy claim matches how drafts are actually protected"
assert_contains "No account to upload" "landing: no account to upload"
assert_contains "private to whoever holds its link" "landing: secret by link"
assert_not_contains "nobody else here can see your work" "landing: no false privacy claim"
# test "is a single document, not a layout nested inside itself"
assert_eq "$(grep -o '<!DOCTYPE html>' "$BODY_F" | wc -l | tr -d ' ')" "1" "landing: exactly one document"
# test "does not carry the scaffold auth menu, which would duplicate its own header"
assert_matches 'MARGINALIA|Marginalia' "landing: it has its brand"
assert_not_contains "menu menu-horizontal" "landing: and no scaffold menu"
assert_not_contains '<header class="mg-bar">' "landing: no app header"
assert_not_contains 'id="flash-group"' "landing: no flash group (a flash set by a redirect to / is never displayed)"
# test "the margin carries the product's own notes on the pitch, including ones that argue with it"
assert_contains "annotating its own pitch" "landing: notes annotate the pitch"
assert_contains "they read as a contradiction" "landing: one pushes back on the copy"
assert_contains "This section argues with the one before it" "landing: and one argues with the section before"
# test "a logged-out visitor's CTAs go straight at the upload -- no account needed"
assert_contains 'href="/works/new"' "landing: a visitor's calls to action go to the upload"
assert_contains 'class="cta ghost">Log in</a>' "landing: and a visitor is offered a log-in"
assert_not_contains "Your drafts" "landing: not 'Your drafts'"
# test "the margin offers sign-up actions, not just commentary"
assert_contains "Find yours" "landing: Find yours"
assert_contains "Try to break it" "landing: Try to break it"
# test "worked examples are present and play in sequence"
assert_contains "Which thread did I set up and never pay off?" "landing: a worked question"
assert_contains "Rewrite my opening paragraph so it hits harder." "landing: another"
assert_contains 'style="--i:0"' "landing: turns are staggered by index"
assert_contains 'style="--i:2"' "landing: to the third"
# test "everything that animates is marked for the scroll observer"
assert_contains "data-reveal" "landing: marked for the observer"
REVEALS="$(count_of data-reveal)"
if [ "$REVEALS" -ge 10 ]; then _ok "landing: the rail is revealed progressively ($REVEALS)"; else _bad "landing: the rail is revealed progressively" "expected >= 10, got $REVEALS"; fi
assert_contains 'phx-hook="Reveal"' "landing: the Reveal hook is on div#landing"
assert_contains '<div id="landing"' "landing: div#landing"
assert_eq "$(db_count users)" "$USERS_BEFORE" "landing: no guest is made for a visitor"
assert_matches '<style>' "landing: the stylesheet is inline"
assert_contains "--mg-accent:#8a3324" "landing: with the page's tokens"
# the stylesheet, byte for byte
EXTRACT="$E2E_DIR/../notes/web-public-extracts/landing.css"
if [ -f "$EXTRACT" ]; then
  sed -n '/^<style>$/,/^<\/style>$/p' "$BODY_F" | sed '1d;$d' > "$T/css.got"
  if cmp -s "$T/css.got" "$EXTRACT"; then _ok "landing: the inline stylesheet is the extract, byte for byte"; else _bad "landing: the inline stylesheet is the extract, byte for byte" "$(diff "$T/css.got" "$EXTRACT" | head -5)"; fi
else
  skip "landing: the stylesheet extract is not beside the tests"
fi
cp "$BODY_F" "$T/landing.html"
# test "just the notes drops the prose and keeps the rail"
evm toggle_notes '{}' /
assert_contains 'class="mg notes-only"' "landing: just the notes switches the mode on"
assert_contains 'class="mg-toggle on"' "landing: and the button shows it"
assert_contains "annotating its own pitch" "landing: the notes survive the switch"
assert_not_contains "space-y-4" "landing: and the region is the bare layout's, not the app's"
evm toggle_notes '{}' /
assert_not_contains 'class="mg notes-only"' "landing: switches off"
get /
assert_not_contains 'class="mg notes-only"' "landing: a plain visit starts with the prose showing"
# test "a logged-in writer's CTAs go to the upload page, not back to registration" and "pointed at their drafts"
new_visitor writer
ensure_user "$(new_email)" "$PASS"
get /
assert_contains 'href="/works/new"' "landing: a writer's calls to action go to the upload page"
assert_not_contains 'href="/users/register"' "landing: not back to registration"
assert_contains "Your drafts" "landing: a writer is pointed at their drafts"
assert_not_contains 'class="cta ghost">Log in</a>' "landing: and is not offered a log-in"

# ---- landing_features_test (the half a visitor can see)
cp "$T/landing.html" "$BODY_F"
tr '\n' ' ' < "$T/landing.html" | sed -E 's/[[:space:]]+/ /g' > "$T/landing.flat"
cp "$T/landing.flat" "$BODY_F"
for s in "Where you are in twelve sections" "Every change, kept" "read forwards" "2,500 words" "working under" "never tell the second pass what the first concluded" "git log -p" "one per draft" "111 stacked pull requests" "It found sixty-five" \
         "Section 7 of 12, asked what is in it" "The Changes tab, after one accepted rewrite" "111 chapters, read forwards" "temper_date" "cuts the gloss" "65 of the 111 are walked back by a later chapter" \
         "It goes and looks" "the quote was fetched from your book" "search_manuscript" "read_passage" "find_exact" "misreading" "records a ruling" \
         "Two drafts, and what runs between them" "A novel and the story it came out of" "the direction is part of the claim" "not merely that the two are about fathers" "cluster" \
         "Forty pull requests in, one edited draft out" "<b>1</b> find" "<b>2</b> narrow" "<b>3</b> land" "<b>4</b> read" "<b>5</b> compose" "<b>6</b> edit" "<b>7</b> condense" "<b>8</b> compare" "@today" "no relative dates"; do
  assert_contains "$s" "landing features: says '$s'"
done
assert_not_contains "250 words" "landing features: the rewrite section is not still quoting an old limit"
assert_contains "data-demo" "landing features: demos declare themselves"
assert_contains 'data-step="1"' "landing features: with their steps"
assert_contains 'data-step="4"' "landing features: up to four"
assert_contains "<del" "landing features: the diff demo marks removals"
assert_contains "<ins" "landing features: and additions"
# every tool the page shows is one the editor defines (lib/marginalia/chat/editor.ex) -- the source-reading half is a skip
TOOLS="$(grep -o '<span class="tool">[a-z_]*</span>' "$BODY_F" | sed 's/<[^>]*>//g' | sort -u | tr '\n' ' ')"
case "$TOOLS" in *search_manuscript*read_passage*|*find_exact*) _ok "landing features: the page shows the editor's tools ($TOOLS)" ;; *) _bad "landing features: the page shows tools" "tools: $TOOLS" ;; esac
skip "landing features: each tool, edge kind and import qualifier shown is one chat/editor.ex, analysis/linker.ex and import/query.ex define (those are Elixir source reads; the Blimp port checks them in the libraries' Temper tests)"
# the edge kinds the linking demo draws are the six the linker can emit
KINDS="$(grep -o 'class="d-edge[^"]*"[^>]*><i>[a-z_]*</i>' "$BODY_F" | sed 's/.*<i>\([a-z_]*\)<\/i>/\1/' | sort -u)"
BAD_KIND=""
for k in $KINDS; do
  case " develops pays_off requires tension answers echoes " in *" $k "*) ;; *) BAD_KIND="$BAD_KIND $k" ;; esac
done
if [ -n "$KINDS" ] && [ -z "$BAD_KIND" ]; then _ok "landing features: every edge kind it shows is one the linker can emit"; else _bad "landing features: every edge kind it shows is one the linker can emit" "shown: $KINDS; unknown:$BAD_KIND"; fi
for k in develops pays_off requires tension answers echoes; do
  assert_contains "$k" "landing features: names the kind $k"
done
# the qualifiers the import section prints: stat: is the typo whose refusal it demonstrates
QUALS="$(grep -o '<code[^>]*>[a-z]*:' "$BODY_F" | sed 's/<[^>]*>//; s/://' | sort -u | tr '\n' ' ')"
case "$QUALS" in *stat*) _ok "landing features: the worked example of a refused qualifier is on the page ($QUALS)" ;; *) _bad "landing features: the refused qualifier example" "qualifiers: $QUALS" ;; esac
# anchors
SECTIONS="$(grep -o '<section class="sec head"' "$BODY_F" | wc -l | tr -d ' ')"
IDS="$(grep -o '<section class="sec head" id="[a-z-]*"' "$BODY_F" | sed 's/.*id="//; s/"//')"
IDCOUNT="$(printf '%s\n' "$IDS" | grep -c .)"
assert_eq "$IDCOUNT" "$SECTIONS" "landing features: every section is addressable"
assert_eq "$(printf '%s\n' "$IDS" | sort | uniq -d | wc -l | tr -d ' ')" "0" "landing features: and no id is used twice"
assert_eq "$SECTIONS" "18" "landing features: eighteen sections"
for id in changes summaries links stacks graph rewrites; do
  assert_contains "id=\"$id\"" "landing features: /#$id is the link for its feature"
done
# the example documents
SEEITS="$(grep -o 'class="seeit"><a[^>]*href="[^"]*"' "$BODY_F" | sed 's/.*href="//; s/"//')"
NSEE="$(printf '%s\n' "$SEEITS" | grep -c .)"
if [ "$NSEE" -ge 6 ]; then _ok "landing features: a feature described is shown ($NSEE examples)"; else _bad "landing features: a feature described is shown" "only $NSEE examples"; fi
NUNIQ="$(printf '%s\n' "$SEEITS" | sort -u | grep -c .)"
if [ "$NUNIQ" -ge 3 ]; then _ok "landing features: each one is a different thing to look at"; else _bad "landing features: each one is a different thing to look at" "$NUNIQ distinct"; fi
PRIVATE=""
for p in $SEEITS; do
  case "$p" in /drafts*|/cases*|/reading*|/linked*) ;; *) PRIVATE="$PRIVATE $p" ;; esac
done
if [ -z "$PRIVATE" ]; then _ok "landing features: the examples are public routes, not ones behind a login"; else _bad "landing features: the examples are public" "not public:$PRIVATE"; fi
# every link out of the page is one the router serves (a route of another group that has not landed answers 404: a skip, not a failure)
PATHS="$(grep -o 'href="/[^"#?]*' "$BODY_F" | sed 's/href="//' | grep -v '^/assets' | sort -u)"
for p in /cases /reading/a-temper-backend-for-blimp-pull-request-stack /works/new; do
  case " $(echo $PATHS) " in *" $p "*) _ok "landing features: links to $p" ;; *) _bad "landing features: links to $p" ;; esac
done
new_visitor linker
for p in $PATHS; do
  get "$p"
  case "$STATUS" in
    404) skip "landing features: $p answers 404 (a page of a group that has not landed)" ;;
    5*|000) _bad "landing features: $p is linked from the homepage and is a route" "status $STATUS" ;;
    *) _ok "landing features: $p is linked from the homepage and is a route ($STATUS)" ;;
  esac
done
# the cases page resolves
get /cases
assert_status 200 "landing features: the cases page resolves"
get /reading/a-temper-backend-for-blimp-pull-request-stack
case "$STATUS" in
  404) skip "landing features: /reading/<slug> is not served yet (pages_drafts)" ;;
  303|302) assert_redirect_to "/reading" "landing features: the published reading degrades to /reading when there is nothing there" ;;
  *) _ok "landing features: the published reading answers ($STATUS)" ;;
esac

# og_test: the card image is actually there
PNG="$E2E_DIR/../static/images/og-cases.png"
if [ -f "$PNG" ]; then
  DIM="$(python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print(struct.unpack(">II", d[16:24])[0], struct.unpack(">II", d[16:24])[1])' "$PNG" 2>/dev/null)"
  assert_eq "$DIM" "2400 1260" "og: the card image is 2400x1260 (1.91:1 at 2x)"
  get /images/og-cases.png
  assert_status 200 "og: and is served"
else
  _bad "og: the card image is actually there" "$PNG is missing"
fi
