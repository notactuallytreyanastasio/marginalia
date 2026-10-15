#!/usr/bin/env bash
# cases_fixtures.sh: what 40_cases.sh and 90_cases_chat.sh share. Source it after lib.sh:
#   . "$(dirname "$0")/../cases_fixtures.sh"
#
# The Elixir tests built their data with Works.create_work, Cases.place and Links.store_edges.
# Here the owner registers through /users/register, as a person would, and the documents, nodes,
# links and edges are inserted with sqlite3 into the app's own database (MARGINALIA_DB), because
# producing an anchored read by hand is what the read pipeline is for and not what these pages
# are about. The ids are in the 9000s so nothing another file uploads can collide with them, and
# every insert is OR IGNORE so a second file placing the same case is a no-op.
#
# The owner is whoever accountsOwnerEmail() says: OWNER_EMAIL, default bobbbygrayson@gmail.com.
# (e2e.sh exports MARGINALIA_OWNER_EMAIL, which the accounts library does not read.)

OWNER="${OWNER_EMAIL:-bobbbygrayson@gmail.com}"
PASS='hello world!'

sql() { sqlite3 -cmd '.timeout 8000' "$MARGINALIA_DB" "$1"; }

# main_to_body: an event's reply is JSON; make its #main region the body, so the assertions
# read HTML and not escaped HTML. The flash and the redirect are kept in variables.
main_to_body() {
  FLASH_ERR=""; FLASH_INFO=""; REDIRECT=""
  if command -v jq >/dev/null 2>&1; then
    FLASH_ERR="$(jq -r '.flash.error // ""' "$BODY_F" 2>/dev/null)"
    FLASH_INFO="$(jq -r '.flash.info // ""' "$BODY_F" 2>/dev/null)"
    REDIRECT="$(jq -r '.redirect // ""' "$BODY_F" 2>/dev/null)"
    jq -r '.regions["#main"] // ""' "$BODY_F" > "$T/main" 2>/dev/null && cp "$T/main" "$BODY_F"
  fi
}

# evm NAME PAYLOAD PATH: an event, and its region as the body
evm() { ev "$1" "$2" "$3"; main_to_body; }

count_of() { # TEXT   how many times TEXT occurs in the body
  grep -oF -- "$1" "$BODY_F" | wc -l | tr -d ' '
}

# cases_owner: register and log in the owner (in the current jar), set OWNER_ID
cases_owner() {
  ensure_user "$OWNER" "$PASS"
  OWNER_ID="$(sql "select id from users where email = '$OWNER'")"
  if [ -z "$OWNER_ID" ]; then
    _bad "cases: the owner $OWNER could not be registered"
    exit 1
  fi
  WORDS="$(words 200)"
}

# mkdoc ID SLUG TITLE COLLECTION ROLE HELD IMPRESSION SOURCE
#   a read draft in a collection: one section whose first paragraph holds the quote, one beat anchored to it
mkdoc() {
  local id="$1" slug="$2" title="$3" coll="$4" role="$5" held="$6" fi="${7:-}" src="${8:-}"
  local sentence="A sentence long enough to be a section."
  [ "$held" = 1 ] && sentence="$sentence We hold that the removal power is the President''s alone."
  local fi_sql="NULL" src_sql="NULL"
  [ -n "$fi" ] && fi_sql="'$fi'"
  [ -n "$src" ] && src_sql="'$src'"
  local nl="char(10) || char(10)"
  sql "
    INSERT OR IGNORE INTO works (id, user_id, title, body, word_count, status, first_impression, slug, source_url, collection, collection_role)
    VALUES ($id, $OWNER_ID, '$title', '# $title' || $nl || '$sentence' || $nl || '$WORDS', 200, 'read', $fi_sql, '$slug', $src_sql, '$coll', '$role');
    INSERT OR IGNORE INTO sections (id, work_id, ordinal, title, body, word_count, status)
    VALUES ($id, $id, 1, '$title', '$sentence' || $nl || '$WORDS', 200, 'read');
    INSERT OR IGNORE INTO nodes (id, work_id, section_id, node_type, title, body, quote, ordinal, status)
    VALUES ($id, $id, $id, 'beat', 'a beat in the $role', 'what the $role is doing here', 'A sentence long enough', 0, 'pending');
  "
}

# mklink LINKID A B TYPE WHY SUMMARY EDGEID   (a and b are work ids; nodes have the work's id)
mklink() {
  sql "
    INSERT OR IGNORE INTO links (id, a_work_id, b_work_id, status, summary) VALUES ($1, $2, $3, 'linked', '$6');
    INSERT OR IGNORE INTO link_edges (id, link_id, from_id, to_id, edge_type, rationale, ordinal) VALUES ($7, $1, $2, $3, '$4', '$5', 0);
  "
}

# "Some v. Case" (case_page_test, case_read_test): an argument, an opinion and a dissent, the opinion
# linked to each, the dissent to the argument.
cases_some_v_case() {
  mkdoc 9201 s2ar "Some v. Case — Argument: Counsel" "Some v. Case" argument 0
  mkdoc 9202 s2op "Some v. Case — Opinion" "Some v. Case" opinion 0
  mkdoc 9203 s2di "Some v. Case — Dissent" "Some v. Case" dissent 0
  mklink 9201 9202 9203 tension "They part on consent." "tension between them." 9201
  mklink 9202 9202 9201 answers "The lectern already settled this." "answers between them." 9202
  mklink 9203 9203 9201 echoes "Dissent and counsel agree here." "echoes between them." 9203
  EDGE_TENSION=9201
  EDGE_ANSWERS=9202
}
