#!/usr/bin/env bash
# 30_public.sh: the pages a stranger can read: error pages, /drafts, /drafts/:slug[/changes],
# /linked, /sitemap.xml, robots.txt, Open Graph tags.
# SKELETON. Runs only when "30_public.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md parts 7 and 9), 50 tests:
#   error_html_test (3), error_json_test (2), error_page_test (6), public_drafts_test (7),
#   public_changes_test (6), draft_render_test (4), linked_index_test (5), public_linked_test (5),
#   sitemap_test (6), og_test (6).
# The owner of the site is MARGINALIA_OWNER_EMAIL=owner@example.com (set by e2e.sh): only
# that account's drafts are public. The Elixir tests built data with Works.create_work; here
# the owner registers and uploads through /works/new, exactly as a person would.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

OWNER=owner@example.com
PASS='hello world!'
B300="# One

$(words 300)"

# the owner's session in one jar, a stranger's in another, an anonymous visitor in a third
new_visitor owner;    ensure_user "$OWNER" "$PASS"; OWNER_JAR="$JAR"
new_visitor stranger; ensure_user "$(new_email)" "$PASS"; STRANGER_JAR="$JAR"
JAR="$OWNER_JAR";    upload_text "A draft of my own" "$B300";      MINE="$(draft_slug)"
JAR="$STRANGER_JAR"; upload_text "Somebody else's" "$B300";        THEIRS="$(draft_slug)"
new_visitor visitor

# ======================= error_page_test / error_html_test =====================
# test "404 is a page, not the words Not Found"            (error_html: "404 renders a page through the template layer")
get /no/such/page
assert_status 404 "error: an unknown path is a 404"
assert_contains "<!DOCTYPE html>" "error: the 404 is a whole document"
assert_contains "Nothing at that address" "error: the 404 says Nothing at that address"
assert_not_contains ">Not Found<" "error: and is not the bare words Not Found"
# test "it offers somewhere to go"
for p in / /cases /drafts /reading; do
  assert_contains "href=\"$p\"" "error: the 404 links to $p (a dead end with no way out of it)"
done
# test "neither is indexed"
assert_contains '<meta name="robots" content="noindex"' "error: the 404 is noindex"
# test "500 does not blame the visitor" / "neither is indexed" (500) / "they depend on nothing that could also be broken"
skip "error: the 500 page says 'Something broke' and 'That is this end, not yours', is noindex, has <style> and no /assets/ (no route raises on purpose; the template is checked by a Temper test)"
# test "anything else keeps the plain status name"       (error_html: "a status with no page of its own still renders its name")
skip "error: a status with no page of its own (403, 418) is just its reason phrase (nothing in the app answers 403/418)"
# error_json_test: "renders 404", "renders 500"
get_json /no/such/page
assert_json_path .errors.detail "Not Found" "error json: a JSON 404 is {errors: {detail: Not Found}}"
skip "error json: a JSON 500 is {errors: {detail: Internal Server Error}} (no route raises on purpose)"

# ============================ public_drafts_test ==============================
new_visitor visitor
# test "a stranger with no account sees the owner's drafts listed"
get /drafts
assert_status 200 "drafts: /drafts is open"
assert_contains "A draft of my own" "drafts: lists the owner's draft"
assert_contains "302 words" "drafts: shows its word count (the heading counts: '# One' + 300 words)"
# test "somebody else's draft is not on the list"
assert_not_contains "Somebody else's" "drafts: does not list a stranger's draft"
# test "somebody else's draft is not served by slug either"
get "/drafts/$THEIRS"
assert_redirect_to "/drafts" "drafts: a stranger's draft by slug goes back to /drafts"
# test "the owner's draft reads, with no account, and is indexable"
get "/drafts/$MINE"
assert_status 200 "drafts: the owner's draft opens with no account"
assert_contains "A draft of my own" "drafts: shows the title"
assert_contains "index, follow" "drafts: is indexable (index, follow)"
assert_not_contains "noindex" "drafts: and says noindex nowhere"
# test "the public page carries none of the controls that write or spend"
for c in summarise_document summarise suggest_rewrite edit_block save_block start_read; do
  assert_not_contains "$c" "drafts: the public page has no $c (it is reachable from nowhere on it)"
done
# test "reading one mints no account for the visitor"
n0="$(db_count users)"
new_visitor crawler
get "/drafts/$MINE"
n1="$(db_count users)"
if [ -n "$n0" ]; then assert_eq "$n1" "$n0" "drafts: a public page mints no user row per crawler (a table that fills with crawlers)"; else skip "drafts: no user minted by reading (sqlite3 CLI or the db file is missing)"; fi
# test "a slug nobody owns goes back to the list rather than erroring"
get /drafts/not-a-real-slug
assert_redirect_to "/drafts" "drafts: an unknown slug goes back to /drafts"

# ============================= public_changes_test ============================
# Setup the Elixir test did with Works.replace_block: the owner edits one paragraph in the
# read view (events edit_block + save_block). ASSUMPTION: a draft can be edited before it is
# read; if the read view requires status "read", run the fake-LLM read first (HARD.beats.json
# answers beats, first_impression.spine.json the spine).
CH_BODY="# One

ALPHA the first paragraph. $(words 150)

BRAVO the second. $(words 150)"
JAR="$OWNER_JAR"; upload_text "Mine" "$CH_BODY"; CH="$(draft_slug)"
get "/works/$CH?view=read"
REF="$(grep -o 'id="block-[^"]*"' "$BODY_F" | grep -v 'block-s[0-9]*h' | sed -n 2p | sed 's/id="block-\(.*\)"/\1/')"
ev edit_block "{\"ref\":\"$REF\"}" "/works/$CH?view=read"
ev save_block "{\"text\":$(json_str "AMENDED the first paragraph. $(words 150)")}" "/works/$CH?view=read"
new_visitor visitor
# test "a stranger sees what the draft used to say"
get "/drafts/$CH/changes"
assert_contains "As it arrived" "changes: has the 'As it arrived' section"
assert_contains "ALPHA" "changes: shows the version that was replaced"
assert_contains "AMENDED" "changes: shows the new version"
assert_contains "1 edited" "changes: says 1 edited"
# test "and where the change came from"
skip "changes: shows the origin 'rewrite' and the note 'cuts the gloss' (needs an applied rewrite with a note: the rewrite panel + fake LLM; belongs with 70_work_show)"
# test "the draft page links to it once there is something to show"
get "/drafts/$CH"
assert_contains "1 change since it arrived" "changes: the draft page says 1 change since it arrived"
assert_contains "/drafts/$CH/changes" "changes: and links to /drafts/<slug>/changes"
# test "somebody else's draft has no public diff either"
get "/drafts/$THEIRS/changes"
assert_redirect_to "/drafts" "changes: a stranger's draft has no public diff"
# test "an unchanged draft says so instead of showing an empty table"
get "/drafts/$MINE/changes"
assert_contains "Nothing has been changed yet" "changes: an unchanged draft says Nothing has been changed yet"
assert_not_contains "As it arrived" "changes: and shows no empty table"
# test "it carries no control that writes"
get "/drafts/$CH/changes"
for c in edit_block save_block suggest_rewrite apply_rewrite summarise; do
  assert_not_contains "$c" "changes: the diff page has no $c"
done

# ============================== draft_render_test =============================
DR_BODY='# The post

At 04:47 UTC agent-7 implemented the Guideline step
reset for lock delay. The idea came from agent-8.

> agent-8 logged that the cap locks a piece. Agent-7
> read it.

```
line one
line two
```

- one. Two.
- three.

Every node, by minute. '"$(words 200)"
JAR="$OWNER_JAR"; upload_text "The post" "$DR_BODY"; DR="$(draft_slug)"
new_visitor visitor
get "/drafts/$DR"
# test "sentences of a paragraph run on; the draft's blank lines are the only breaks"
assert_not_contains "<br" "render: no <br> between sentences"
assert_contains "<p>At 04:47 UTC agent-7 implemented the Guideline step reset for lock delay.
The idea came from agent-8.</p>" "render: sentences of a paragraph run on, one per line, in one <p>"
# test "a blockquote renders as one quoted paragraph"
assert_contains "<p>agent-8 logged that the cap locks a piece.
Agent-7 read it.</p>" "render: a blockquote is one quoted paragraph"
# test "code keeps its line breaks and a list keeps its items"
assert_contains "<code>line one
line two
</code>" "render: code keeps its line breaks"
assert_contains "<li>one. Two.</li>" "render: a list item with two sentences stays whole"
assert_contains "<li>three.</li>" "render: the next list item"
# test "the changes page shows the sentence that changed, on its own"
JAR="$OWNER_JAR"
get "/works/$DR?view=read"
REF="$(grep -o 'id="block-[^"]*"' "$BODY_F" | sed -n 2p | sed 's/id="block-\(.*\)"/\1/')"
ev edit_block "{\"ref\":\"$REF\"}" "/works/$DR?view=read"
ev save_block "{\"text\":$(json_str "At 04:47 UTC agent-7 implemented the Guideline step reset for lock delay.
The idea came from agent-8's decision.")}" "/works/$DR?view=read"
new_visitor visitor
get "/drafts/$DR/changes"
assert_contains "1 edited" "render: the changes page says 1 edited"
assert_contains '<div class="mg-diff-row change">' "render: one diff row is a change"
assert_contains 'class="w ins"' "render: the new words are marked ins"
assert_contains "decision." "render: and include the added words"
assert_contains 'class="w del"' "render: the old words are marked del"

# ====================== linked_index_test / public_linked_test ================
# The Elixir tests inserted nodes and LinkEdges straight into the database. Through HTTP a pair
# is made by uploading two owner drafts, reading both (fake LLM: HARD.beats.json), starting a
# link in the read view and waiting for it (a Linker reply is not scripted yet: add
# fixtures/llm/<needle>.link.json when the linker prompt is ported). Until make_linked_pairs
# exists the assertions below are skipped, not dropped.
make_linked_pairs() { return 1; }   # TODO(page agent for /linked): build "The novel" + "The story" (pays_off: "Nine pays off the promise the story made."), a tension pair and an unrelated pair
if make_linked_pairs; then
  new_visitor visitor
  get /linked
  # linked_index: "a pair with a tension outranks a pair with more edges"
  assert_matches 'tension' "linked: the pair with a tension is listed first"
  # linked_index: "the page says how many of them contain one"
  assert_contains "2 pairs" "linked: says 2 pairs"
  assert_contains "1 of them contain a tension" "linked: says 1 of them contain a tension"
  assert_contains "1 tension" "linked: shows 1 tension on the row"
  # linked_index: "the filter narrows by either title" / "a filter matching nothing says so rather than showing an empty list"
  ev filter '{"q":"Argues"}' /linked
  assert_contains "Argues one" "linked: filter Argues keeps Argues one"
  assert_not_contains "Quiet one" "linked: filter Argues drops Quiet one"
  ev filter '{"q":"nothing here"}' /linked
  assert_contains "Nothing matches" "linked: a filter matching nothing says Nothing matches"
  # public_linked: "a stranger sees the pair and its edges"
  get "/linked/$LINK_ID"
  assert_contains "The novel" "linked pair: shows the first draft"
  assert_contains "The story" "linked pair: shows the second draft"
  assert_contains "He stops in the doorway" "linked pair: shows the from-beat"
  assert_contains "pays off" "linked pair: shows the edge type with the underscore as a space"
  assert_contains "Nine pays off the promise the story made." "linked pair: shows the rationale"
  # public_linked: "somebody else's pair is not readable" / "a pair that found nothing is not offered" / "the index lists the owner's pairs only"
  get "/linked/$THEIR_LINK_ID"; assert_redirect_to "/linked" "linked pair: a stranger's pair redirects to /linked"
  get /linked; assert_not_contains "Unrelated" "linked: a pair with no edges is not offered"
  assert_not_contains "Their first" "linked: the index lists the owner's pairs only"
  # public_linked: "it carries no control that writes"
  get "/linked/$LINK_ID"
  for c in make pick relink edit_block suggest_rewrite; do assert_not_contains "phx-click=\"$c\"" "linked pair: no $c control"; assert_not_contains "data-ev=\"$c\"" "linked pair: no $c event"; done
else
  skip "linked: a tension outranks more edges; '2 pairs', '1 of them contain a tension', '1 tension'; filter 'Argues' keeps 'Argues one', drops 'Quiet one'; 'Nothing matches' (needs a linked pair; linker reply not scripted)"
  skip "linked pair: a stranger sees 'The novel', 'The story', 'He stops in the doorway', 'pays off', 'Nine pays off the promise the story made.'; somebody else's pair redirects to /linked; an edgeless pair ('Unrelated') is not offered; no make/pick/relink/edit_block/suggest_rewrite control"
fi

# ================================ sitemap_test ================================
new_visitor visitor
get /sitemap.xml
# test "it is xml and lists the public entry points"
assert_status 200 "sitemap: /sitemap.xml is 200"
assert_contains "<?xml" "sitemap: is xml"
assert_contains "<urlset" "sitemap: has a urlset"
for p in / /cases /drafts /linked /reading; do
  assert_matches "<loc>https?://[^<]*$p</loc>" "sitemap: lists $p"
done
# test "the owner's drafts are in it"
assert_contains "/drafts/$MINE</loc>" "sitemap: the owner's draft is in it"
# test "nobody else's draft is"
assert_not_contains "$THEIRS" "sitemap: nobody else's draft is"
# test "a draft with no changes has no changes page listed"
assert_not_contains "/drafts/$MINE/changes" "sitemap: a draft with no changes has no changes page (hundreds of empty tables for a crawler otherwise)"
# test "a draft with changes does"   (the sitemap is cached; it may need a moment)
assert_waits /sitemap.xml "/drafts/$CH/changes</loc>" 15 "sitemap: a draft with changes has its changes page listed"
# test "robots.txt points at it"
get /robots.txt
assert_contains "Sitemap:" "robots: names a Sitemap:"
assert_contains "/sitemap.xml" "robots: points at /sitemap.xml"
assert_contains "Disallow: /works/" "robots: the private pages stay disallowed"

# ================================== og_test ===================================
# test "the front page keeps the product's own card"
get /
assert_matches '/images/og\.png' "og: the front page's og:image is /images/og.png"
assert_matches 'og:url" content="[^"]*/"' "og: the front page's og:url ends with a slash"
# describe "the cases micro-site" (all four need a placed case, see 40_cases.sh):
skip "og: /cases has its own card: og:title 'The term, read closely', og:image and twitter:image /images/og-cases.png, og:image:alt 'dissent arguing with that exact sentence'"
skip "og: the /cases description counts the corpus ('1 Supreme Court cases, 1 documents') and says 'anchored to a sentence in both'"
skip "og: /cases, /cases/some-v-case (og:title 'Some v. Case') and /cases/some-v-case/read each declare their own og:url"
skip "og: the canonical link on /cases/some-v-case equals its og:url"
# test "the card image is actually there"
get /images/og-cases.png
assert_status 200 "og: /images/og-cases.png is served"
dims="$(head -c 24 "$BODY_F" | tail -c 8 | od -An -tx1 | tr -d ' \n')"
assert_eq "$dims" "00000960000004ec" "og: the card is 2400x1260 (1.91:1 at 2x, what every card wants)"
