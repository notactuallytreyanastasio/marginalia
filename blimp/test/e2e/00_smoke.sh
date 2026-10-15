#!/usr/bin/env bash
# 00_smoke.sh: the app is up and serves its basics. Runs against the real app and the stub.
. "$(dirname "$0")/../lib.sh"

get /
assert_status 200 "/ is 200"
assert_contains "Marginalia" "/ mentions Marginalia"

get /assets/css/app.css
assert_status 200 "/assets/css/app.css is 200"
assert_header content-type 'text/css' "/assets/css/app.css is served as text/css"
want="$(stat -f%z "$E2E_DIR/../static/css/app.css" 2>/dev/null || stat -c%s "$E2E_DIR/../static/css/app.css")"
got="$(wc -c < "$BODY_F" | tr -d ' ')"
assert_eq "$got" "$want" "/assets/css/app.css is byte-for-byte the committed file ($want bytes)"

get /nonexistent
assert_status 404 "/nonexistent is 404"

get /users/log-in
assert_status 200 "/users/log-in is 200"
assert_contains "<form" "/users/log-in has a form"

# a visitor with no account is either redirected somewhere or minted a guest; either way
# the works page is what they end up on
new_visitor smoke
get_follow /works
assert_status 200 "/works answers 200 after following redirects"

get /sitemap.xml
assert_status 200 "/sitemap.xml is 200"
assert_contains "<urlset" "/sitemap.xml has a urlset"
