#!/usr/bin/env bash
# lib.sh: helpers for blimp/test/e2e/*.sh. Source it:  . "$(dirname "$0")/../lib.sh"
#
# Plain bash 3.2 (macOS /bin/bash) plus curl; jq is used when present.
#
# Environment
#   E2E_BASE   base url of the app under test (default http://127.0.0.1:${PORT:-4000})
#   E2E_FAKE   base url of fake_llm (set by e2e.sh; used to read its log)
#
# State (per test file, because each file is its own process)
#   JAR      cookie jar (curl -b/-c); `new_visitor [name]` switches to a fresh one
#   STATUS   http status of the last request (final hop if following redirects)
#   HEAD_F   file holding the response headers of the last request (all hops)
#   BODY_F   file holding the response body of the last request
#   LOCATION Location header of the last response ("" if none, CR stripped)
#   CSRF     last csrf token seen in a <meta name="csrf-token"> (sent as x-csrf-token
#            and as _csrf_token on form posts when non-empty)
#
# Every assertion prints one TAP-style line: "ok - desc" or "not ok - desc", and on
# failure a few "# " diagnostic lines. e2e.sh counts the "ok"/"not ok" lines.
# Skips print "ok - ... # SKIP" and are counted separately.

BASE="${E2E_BASE:-http://127.0.0.1:${PORT:-4000}}"
E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/e2e.XXXXXX")"
trap 'rm -rf "$T"' EXIT
JAR="$T/jar.default"
HEAD_F="$T/head"
BODY_F="$T/body"
STATUS=""
LOCATION=""
CSRF=""
: > "$HEAD_F"; : > "$BODY_F"

# ---- requests -----------------------------------------------------------

new_visitor() { JAR="$T/jar.${1:-$RANDOM$RANDOM}"; CSRF=""; }

_after() {
  LOCATION="$(grep -i '^location:' "$HEAD_F" | tail -1 | sed -e 's/^[^:]*: *//' -e 's/\r$//')"
  local tok
  tok="$(sed -n 's/.*<meta name="csrf-token" content="\([^"]*\)".*/\1/p' "$BODY_F" | head -1)"
  [ -n "$tok" ] && CSRF="$tok"
  return 0
}

# _curl METHOD PATH [curl args...]; PATH may be absolute (http...) or start with /
_curl() {
  local method="$1" path="$2"; shift 2
  local url="$path"
  case "$path" in http*) ;; *) url="$BASE$path" ;; esac
  : > "$HEAD_F"; : > "$BODY_F"
  STATUS="$(curl -s -S --max-time 60 -X "$method" -b "$JAR" -c "$JAR" \
    -H 'Expect:' -D "$HEAD_F" -o "$BODY_F" -w '%{http_code}' "$@" "$url")" || STATUS="000"
  _after
}

get()        { _curl GET "$1"; }
get_follow() { _curl GET "$1" -L; }
head_req()   { _curl HEAD "$1" -I; }
delete()     { _curl DELETE "$1" ${CSRF:+-H "x-csrf-token: $CSRF"}; }

# post PATH 'a=b&c=d'   (urlencoded; the caller encodes). _csrf_token is appended when known.
post() {
  local path="$1" data="${2:-}"
  [ -n "$CSRF" ] && data="${data:+$data&}_csrf_token=$CSRF"
  _curl POST "$path" -H 'content-type: application/x-www-form-urlencoded' --data "$data"
}

# post_json PATH 'json'
post_json() {
  _curl POST "$1" -H 'content-type: application/json' ${CSRF:+-H "x-csrf-token: $CSRF"} --data "$2"
}

# ev NAME 'payload-json' PATH   -> POST /ev/NAME, the way blimp.js sends events
ev() {
  local name="$1" payload="${2:-null}" path="${3:-/}"
  _curl POST "/ev/$name" -H 'x-requested-with: blimp' -H 'content-type: application/json' \
    ${CSRF:+-H "x-csrf-token: $CSRF"} \
    --data "{\"payload\":$payload,\"path\":\"$path\"}"
}

# login EMAIL PASSWORD [remember]   POST /users/log-in (the session controller)
login() {
  get /users/log-in
  local extra=()
  [ "${3:-}" = "remember" ] && extra=(--data-urlencode 'user[remember_me]=true')
  _curl POST /users/log-in --data-urlencode "user[email]=$1" --data-urlencode "user[password]=$2" \
    ${CSRF:+--data-urlencode "_csrf_token=$CSRF"} ${extra[@]+"${extra[@]}"}
}

# register EMAIL PASSWORD   POST /users/register. ASSUMPTION: the app takes the registration
# form as a plain POST with user[email] and user[password] (the Elixir page was a LiveView
# event). If the Blimp page makes it an event, change it here and every file follows.
register() {
  get /users/register
  _curl POST /users/register --data-urlencode "user[email]=$1" --data-urlencode "user[password]=$2" \
    ${CSRF:+--data-urlencode "_csrf_token=$CSRF"}
}

logout() { get /users/log-in >/dev/null 2>&1; _curl POST /users/log-out -d "_method=delete" ${CSRF:+--data-urlencode "_csrf_token=$CSRF"}; }

# upload_draft FILE TITLE [INTENT]   multipart POST /works/new, the plain-form path of the
# Elixir app (work[title], work[body], work[intent]); the file's text becomes work[body]
# (the plain POST has no file input: "Attaching a file needs JavaScript"). Sets LOCATION;
# draft_slug prints the slug from it.
upload_draft() {
  get /works/new
  _curl POST /works/new --form-string "work[title]=$2" -F "work[body]=<$1" --form-string "work[intent]=${3:-}" \
    ${CSRF:+--form-string "_csrf_token=$CSRF"}
}
draft_slug() { printf '%s' "$LOCATION" | sed -e 's#^https\{0,1\}://[^/]*##' -e 's#^/works/##' -e 's#[/?].*$##'; }

# wait_for PATH TEXT SECONDS   poll until the page contains TEXT (a literal string)
wait_for() {
  local path="$1" text="$2" secs="${3:-10}" i=0 n
  n=$((secs * 2))
  while [ "$i" -lt "$n" ]; do
    get "$path"
    grep -qF -- "$text" "$BODY_F" && return 0
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

# ---- assertions ---------------------------------------------------------

_ok()  { echo "ok - $1"; }
_bad() { echo "not ok - $1"; shift; local l; for l in "$@"; do echo "# $l"; done; }

assert_status() { # CODE DESC
  if [ "$STATUS" = "$1" ]; then _ok "$2"; else _bad "$2" "expected status $1, got $STATUS"; fi
}

assert_contains() { # TEXT DESC   (literal, may span lines; in the last response body)
  local body; body="$(cat "$BODY_F")"
  case "$body" in
    *"$1"*) _ok "$2" ;;
    *) _bad "$2" "body does not contain: $1" "status $STATUS, $(wc -c < "$BODY_F" | tr -d ' ') bytes: $(printf '%s' "$body" | head -c 160 | tr '\n' ' ')" ;;
  esac
}

assert_not_contains() { # TEXT DESC
  local body; body="$(cat "$BODY_F")"
  case "$body" in *"$1"*) _bad "$2" "body contains: $1" ;; *) _ok "$2" ;; esac
}

assert_matches() { # EXTENDED-REGEX DESC   (grep -E on the body)
  if grep -qE -- "$1" "$BODY_F"; then _ok "$2"; else _bad "$2" "body does not match /$1/"; fi
}

assert_redirect_to() { # PATH DESC   (3xx and Location is PATH, relative or on BASE)
  local loc="${LOCATION#"$BASE"}"
  case "$STATUS" in
    301|302|303|307|308)
      if [ "$loc" = "$1" ]; then _ok "$2"; else _bad "$2" "expected redirect to $1, got Location: $LOCATION"; fi ;;
    *) _bad "$2" "expected a redirect to $1, got status $STATUS" ;;
  esac
}

assert_header() { # NAME PATTERN DESC   (any header line of that name whose value matches the grep -E PATTERN)
  local vals
  vals="$(grep -i "^$1:" "$HEAD_F" | sed -e 's/^[^:]*: *//' -e 's/\r$//')"
  if printf '%s\n' "$vals" | grep -qE -- "$2"; then _ok "$3"; else _bad "$3" "no $1 header matching /$2/; saw: $(printf '%s' "$vals" | tr '\n' '|')"; fi
}

# assert_json_path JQPATH EXPECTED DESC   e.g. assert_json_path .regions.main.ok true "..."
# With jq: compares `jq -r PATH` to EXPECTED. Without: greps for "last-key": EXPECTED.
assert_json_path() {
  local got
  if command -v jq >/dev/null 2>&1; then
    got="$(jq -r "$1" "$BODY_F" 2>/dev/null)"
    if [ "$got" = "$2" ]; then _ok "$3"; else _bad "$3" "jq $1 = '$got', expected '$2'"; fi
  else
    local key="${1##*.}"
    if grep -qE "\"$key\"[[:space:]]*:[[:space:]]*\"?$2\"?" "$BODY_F"; then _ok "$3"; else _bad "$3" "no \"$key\": $2 in body (no jq)"; fi
  fi
}

assert_cookie() { # NAME DESC  (the jar holds a cookie with that name)
  if grep -qE "[[:space:]]$1[[:space:]]" "$JAR" 2>/dev/null; then _ok "$2"; else _bad "$2" "no cookie $1 in jar"; fi
}

assert_no_cookie() { # NAME DESC
  if grep -qE "[[:space:]]$1[[:space:]]" "$JAR" 2>/dev/null; then _bad "$2" "cookie $1 present"; else _ok "$2"; fi
}

assert_eq() { # GOT EXPECTED DESC
  if [ "$1" = "$2" ]; then _ok "$3"; else _bad "$3" "got '$1', expected '$2'"; fi
}

assert_waits() { # PATH TEXT SECONDS DESC
  if wait_for "$1" "$2" "$3"; then _ok "$4"; else _bad "$4" "'$2' never appeared on $1 within $3 s"; fi
}

# assert_llm_log_contains TEXT DESC   (fake_llm's request log, if e2e.sh gave us one)
assert_llm_log_contains() {
  if [ -n "${E2E_LLM_LOG:-}" ] && grep -qF -- "$1" "$E2E_LLM_LOG"; then _ok "$2"; else _bad "$2" "fake_llm log has no: $1"; fi
}

# ---- small helpers used by the page files ----------------------------------

new_email() { echo "user$RANDOM$RANDOM@example.com"; }
cookie_value() { awk -v n="$1" '$6 == n { v = $7 } END { print v }' "$JAR" 2>/dev/null; }
json_str() { printf '%s' "$1" | jq -Rs . 2>/dev/null || printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }
get_json() { _curl GET "$1" -H 'accept: application/json'; }

# meta_content PROP   content of <meta property|name="PROP" content="..."> in the last body
meta_content() {
  grep -o "<meta[^>]*\(property\|name\)=\"$1\"[^>]*content=\"[^\"]*\"" "$BODY_F" | head -1 | sed 's/.*content="\([^"]*\)"/\1/'
}

# ensure_user EMAIL PASSWORD   register (ignoring "already taken"), then log in; leaves the jar logged in
ensure_user() { register "$1" "$2" >/dev/null; login "$1" "$2" >/dev/null; }

# upload_text TITLE BODY [INTENT]   like upload_draft, with the text given inline
upload_text() {
  get /works/new
  _curl POST /works/new --form-string "work[title]=$1" --form-string "work[body]=$2" --form-string "work[intent]=${3:-}" ${CSRF:+--form-string "_csrf_token=$CSRF"}
}

# llm_calls   how many chat-completions requests fake_llm has logged so far
llm_calls() { grep -c 'POST .*chat/completions' "${E2E_LLM_LOG:-/dev/null}" 2>/dev/null || true; }

# db_count TABLE   rows in the app's sqlite file (MARGINALIA_DB); empty when sqlite3 or the file is missing
db_count() { command -v sqlite3 >/dev/null 2>&1 && [ -f "${MARGINALIA_DB:-}" ] && sqlite3 "$MARGINALIA_DB" "select count(*) from $1" 2>/dev/null; }

# words N   N copies of "word " on stdout
words() { yes 'word ' | head -n "$1" | tr -d '\n'; }

# ---- skipping -------------------------------------------------------------

# skip_unless_implemented: put it first in a skeleton file. The file runs only when its
# name is listed in test/e2e/IMPLEMENTED; otherwise it reports one skip and exits 0.
skip_unless_implemented() {
  local me list
  me="$(basename "${BASH_SOURCE[1]}")"
  list="$E2E_DIR/e2e/IMPLEMENTED"
  if [ -f "$list" ] && grep -vE '^[[:space:]]*(#|$)' "$list" | grep -qxF "$me"; then return 0; fi
  echo "ok - $me skipped: not in test/e2e/IMPLEMENTED # SKIP"
  exit 0
}

# skip DESC   a single skipped assertion
skip() { echo "ok - $1 # SKIP"; }
