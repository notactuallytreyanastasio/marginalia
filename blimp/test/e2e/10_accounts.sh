#!/usr/bin/env bash
# 10_accounts.sh: log in, register, settings, the session controller, the auth plugs.
# SKELETON. Runs only when "10_accounts.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md part 8 and 9), 58 tests:
#   user_live/login_test (5), user_live/registration_test (7), user_live/settings_test (12),
#   controllers/user_session_controller_test (6), user_auth_test (28).
# Titles are listed in IMPLEMENTED. Where a Phoenix test pokes a plug or a socket directly
# the assertion below is the HTTP-visible half of it, and the half that cannot be seen from
# curl is a named `skip` with the reason.
#
# What pages_users implements (the assumptions this file started from, as confirmed or changed):
#   - registration: the form is phx-submit="save" / phx-change="validate" and also a plain
#     POST /users/register (user[email], user[password]); both end at /users/log-in. CONFIRMED.
#   - settings: events validate_email, update_email, validate_password, update_password, and
#     the plain POST /users/update-password. CONFIRMED. The update_password event does the
#     whole change (it does not hand back a "now POST" instruction).
#   - flashes are rendered on the next page that is fetched, once. CONFIRMED.
#   - CHANGED: "/works" is not a page yet (pages_works has not landed), so the logged-in menu
#     is asserted on /users/settings and the logged-out view on /users/log-in and /.
#   - CHANGED: a password change does not renew the session id when the user is the same (the
#     Phoenix rule: other tabs keep their CSRF token); what is rotated is the token row the
#     session points at, and every other device's token is deleted. So "the session token is
#     rotated" is asserted by a second device being logged out, not by the cookie changing.
#   - CHANGED: the email input id is login_form_password_email (the form's id is the prefix),
#     which is what the Phoenix test asserts too.
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented

PASS='hello world!'

# ============================ user_live/login_test ============================
new_visitor login
get /users/log-in
# test "renders login page"
assert_contains "Log in" "login: the page says Log in"
assert_contains "Sign up" "login: the page offers Sign up"

# test "redirects if user logs in with valid credentials"
U1="$(new_email)"
register "$U1" "$PASS" >/dev/null
login "$U1" "$PASS" remember
assert_redirect_to "/" "login: valid credentials redirect to /"

# test "redirects to login page with a flash error if credentials are invalid"
new_visitor login-bad
login "test@email.com" "123456"
assert_redirect_to "/users/log-in" "login: invalid credentials redirect back to /users/log-in"
get /users/log-in
assert_contains "Invalid email or password" "login: the flash says Invalid email or password"

# test "redirects to registration page when the Register button is clicked"
assert_contains 'href="/users/register"' "login: Sign up links to /users/register"
get /users/register
assert_contains "Register" "login: the registration page says Register"

# test "shows login page with email filled in"   (describe: re-authentication, sudo mode)
new_visitor login-sudo
ensure_user "$U1" "$PASS"
get /users/log-in
assert_status 200 "login (signed in): the page stays, no redirect"
assert_contains "You need to reauthenticate" "login (signed in): asks to reauthenticate"
assert_not_contains "Register" "login (signed in): no Register text"
assert_contains "Log in" "login (signed in): still says Log in"
assert_contains "<input type=\"email\" name=\"user[email]\" id=\"login_form_password_email\" value=\"$U1\"" \
  "login (signed in): the email input is filled in with the user's email"

# ========================= user_live/registration_test ========================
new_visitor reg
get /users/register
# test "renders registration page"
assert_contains "Register" "register: the page says Register"
assert_contains "Log in" "register: the page links to Log in"

# test "redirects if already logged in"
new_visitor reg-in
ensure_user "$U1" "$PASS"
get /users/register
assert_redirect_to "/" "register: a signed-in visitor is sent to /"

# test "renders errors for invalid data"
new_visitor reg-invalid
get /users/register
ev validate '{"user":{"email":"with spaces"}}' /users/register
assert_contains "Register" "register: validate keeps the form"
assert_contains "must have the @ sign and no spaces" "register: validate says must have the @ sign and no spaces"

# test "creates the account and sends them to log in"
# (registration goes straight to the log-in form: there is no confirmation email to wait for)
E2="$(new_email)"
register "$E2" "$PASS"
assert_redirect_to "/users/log-in" "register: success redirects to /users/log-in"
login "$E2" "$PASS"
assert_redirect_to "/" "register: the new account logs in at once (confirmed, hashed password)"

# test "requires a password"
new_visitor reg-nopass
register "$(new_email)" ""
assert_matches "can(&#39;|')t be blank" "register: a blank password is can't be blank"

# test "renders errors for duplicated email"
new_visitor reg-dup
register "$U1" "$PASS"
assert_contains "has already been taken" "register: a taken email is has already been taken"

# test "redirects to login page when the Log in button is clicked"
get /users/register
assert_contains 'href="/users/log-in"' "register: Log in links to /users/log-in"

# =========================== user_live/settings_test ==========================
# test "renders settings page"
new_visitor settings
ensure_user "$U1" "$PASS"
get /users/settings
assert_status 200 "settings: signed in gets the page"
assert_contains "Change Email" "settings: Change Email"
assert_contains "Save Password" "settings: Save Password"

# test "redirects if user is not logged in"
new_visitor settings-anon
get /users/settings
assert_redirect_to "/users/log-in" "settings: anonymous is sent to /users/log-in"
get /users/log-in
assert_contains "You must log in to access this page." "settings: the flash says You must log in to access this page."

# test "redirects if user is not in sudo mode"
skip "settings: 11-minute-old session is sent to log-in with 'You must re-authenticate to access this page.' (needs clock control: no way to age a session from curl)"

# describe "update email form"
new_visitor settings-email
E3="$(new_email)"
ensure_user "$U1" "$PASS"
get /users/settings
# test "updates the user email"
ev update_email "{\"user\":{\"email\":\"$E3\"}}" /users/settings
assert_contains "A link to confirm your email" "settings: update_email says A link to confirm your email"
new_visitor settings-email-old
login "$U1" "$PASS"
assert_redirect_to "/" "settings: the old email still logs in until the change is confirmed"

# test "renders errors with invalid data (phx-change)"
new_visitor settings-email2
ensure_user "$U1" "$PASS"
get /users/settings
ev validate_email '{"action":"update_email","user":{"email":"with spaces"}}' /users/settings
assert_contains "Change Email" "settings: validate_email keeps the form"
assert_contains "must have the @ sign and no spaces" "settings: validate_email says must have the @ sign and no spaces"

# test "renders errors with invalid data (phx-submit)"
ev update_email "{\"user\":{\"email\":\"$U1\"}}" /users/settings
assert_contains "Change Email" "settings: update_email with the same email keeps the form"
assert_contains "did not change" "settings: update_email with the same email says did not change"

# describe "update password form"
# test "updates the user password"
new_visitor settings-pw
U4="$(new_email)"
ensure_user "$U4" "$PASS"
JAR_A="$JAR"
new_visitor settings-pw-device-b
login "$U4" "$PASS"
JAR_B="$JAR"
JAR="$JAR_A"
get /users/settings
NEWPASS='a brand new passphrase'
post /users/update-password "user%5Bemail%5D=$U4&user%5Bpassword%5D=a+brand+new+passphrase&user%5Bpassword_confirmation%5D=a+brand+new+passphrase"
assert_redirect_to "/users/settings" "settings: the password form redirects to /users/settings"
get /users/settings
assert_status 200 "settings: this device is logged in again with a fresh token"
assert_contains "Password updated successfully" "settings: the flash says Password updated successfully"
# test: the session token is rotated / disconnect_sessions: every other device's token is deleted
JAR="$JAR_B"
get /users/settings
assert_redirect_to "/users/log-in" "settings: the password change logs the other devices out"
new_visitor settings-pw-new
login "$U4" "$NEWPASS"
assert_redirect_to "/" "settings: the new password logs in"

# test "renders errors with invalid data (phx-change)" and "(phx-submit)"
new_visitor settings-pw2
ensure_user "$U1" "$PASS"
get /users/settings
ev validate_password '{"user":{"password":"too short","password_confirmation":"does not match"}}' /users/settings
assert_contains "Save Password" "settings: validate_password keeps the form"
assert_contains "should be at least 12 character(s)" "settings: validate_password says should be at least 12 character(s)"
assert_contains "does not match password" "settings: validate_password says does not match password"
ev update_password '{"user":{"password":"too short","password_confirmation":"does not match"}}' /users/settings
assert_contains "Save Password" "settings: update_password keeps the form"
assert_contains "should be at least 12 character(s)" "settings: update_password says should be at least 12 character(s)"
assert_contains "does not match password" "settings: update_password says does not match password"

# describe "confirm email"
# test "updates the user email once"
# The mail is a row in the outbox table (nothing sends it); the token is read from there with sqlite3.
if command -v sqlite3 >/dev/null 2>&1 && [ -n "${MARGINALIA_DB:-}" ]; then
  new_visitor settings-confirm
  U5="$(new_email)"; E5="$(new_email)"
  ensure_user "$U5" "$PASS"
  get /users/settings
  ev update_email "{\"user\":{\"email\":\"$E5\"}}" /users/settings
  TOKEN="$(sqlite3 "$MARGINALIA_DB" "select body from outbox where to_addr='$E5' order by id desc limit 1" | grep -o 'confirm-email/[^[:space:]]*' | head -1 | sed 's#confirm-email/##')"
  get "/users/settings/confirm-email/$TOKEN"
  assert_redirect_to "/users/settings" "settings: a good confirm-email link redirects to /users/settings"
  get /users/settings
  assert_contains "Email changed successfully." "settings: the flash says Email changed successfully."
  assert_contains "value=\"$E5\"" "settings: the email form holds the new address"
  # test: "use confirm token again"
  get "/users/settings/confirm-email/$TOKEN"
  assert_redirect_to "/users/settings" "settings: the same link again redirects to /users/settings"
  get /users/settings
  assert_contains "Email change link is invalid or it has expired." "settings: the same link again says Email change link is invalid or it has expired."
  new_visitor settings-confirm-old
  login "$U5" "$PASS"
  assert_redirect_to "/users/log-in" "settings: the old address no longer logs in"
  login "$E5" "$PASS"
  assert_redirect_to "/" "settings: the new address logs in"
else
  skip "settings: confirm-email link (needs sqlite3 and MARGINALIA_DB to read the mail from the outbox table)"
fi
# test "does not update email with invalid token"
get /users/settings/confirm-email/oops
assert_redirect_to "/users/settings" "settings: a bad confirm-email token redirects to /users/settings"
get /users/settings
assert_contains "Email change link is invalid or it has expired." "settings: the flash says Email change link is invalid or it has expired."
# test "redirects if user is not logged in"
new_visitor settings-confirm-anon
get /users/settings/confirm-email/oops
assert_redirect_to "/users/log-in" "settings: confirm-email while anonymous goes to /users/log-in"
get /users/log-in
assert_contains "You must log in to access this page." "settings: confirm-email while anonymous says You must log in to access this page."

# ================== controllers/user_session_controller_test ==================
# test "logs the user in"
new_visitor session
login "$U1" "$PASS"
assert_redirect_to "/" "session: log-in redirects to /"
assert_cookie _marginalia_key "session: a session cookie is set"
# ("/" carries no auth menu on purpose, so the logged-in menu is asserted on a page with the
# app layout: /works is not here yet, so /users/settings)
get /users/settings
assert_contains "$U1" "session: the app layout shows the user's email"
assert_contains "/users/settings" "session: the app layout links to /users/settings"
assert_contains "/users/log-out" "session: the app layout has the log-out form"

# test "logs the user in with remember me"
new_visitor session-remember
login "$U1" "$PASS" remember
assert_header set-cookie '_marginalia_web_user_remember_me=' "session: remember me sets _marginalia_web_user_remember_me"
assert_redirect_to "/" "session: remember me redirects to /"

# test "logs the user in with return to"
new_visitor session-return
get /users/settings
login "$U1" "$PASS"
assert_redirect_to "/users/settings" "session: log-in returns to the page that asked for it"
get /users/settings
assert_contains "Welcome back!" "session: the flash says Welcome back!"

# test "redirects to login page with invalid credentials"
new_visitor session-bad
login "$U1" "invalid_password_zzz"
assert_redirect_to "/users/log-in" "session: bad password redirects to /users/log-in (the ?mode=password is not carried)"
get /users/log-in
assert_contains "Invalid email or password" "session: bad password flash is Invalid email or password"

# test "logs the user out"
new_visitor session-out
login "$U1" "$PASS"
logout
assert_redirect_to "/" "session: log-out redirects to /"
get /
assert_not_contains "$U1" "session: after log-out the email is gone from the menu"
# The controller test read the flash off the conn. The landing page is the bare layout with no
# flash group, so the message is never shown; the page still takes it, so it is gone by the next.
assert_not_contains "Logged out successfully" "session: the landing page has no flash group to show Logged out successfully"
get /users/log-in
assert_not_contains "Logged out successfully" "session: the landing page took the log-out flash, so the next page does not show it"

# test "succeeds even if the user is not logged in"
new_visitor session-out-anon
logout
assert_redirect_to "/" "session: log-out with no session still redirects to /"

# ============================ user_auth_test (28) =============================
# log_in_user/3
new_visitor auth
login "$U1" "$PASS"
# test "stores the user token in the session"
assert_cookie _marginalia_key "auth: log-in stores a session token"
assert_redirect_to "/" "auth: log-in redirects to / by default"
# test "clears everything previously stored in the session" / "keeps session when re-authenticating" /
# "clears session when user does not match when re-authenticating"
skip "auth: session contents are cleared on log-in unless it is the same user (session internals; covered by the Temper unit test of the session store)"
# test "redirects to the configured path" / "clears the return-to path from the session after logging in"
new_visitor auth-return
get /users/settings
login "$U1" "$PASS"
assert_redirect_to "/users/settings" "auth: log-in goes to the stored return-to path"
login "$U1" "$PASS"
assert_redirect_to "/users/settings" "auth: a second log-in as the same user goes to /users/settings (return-to was cleared)"
# test "writes a cookie if remember_me is configured"
new_visitor auth-remember
login "$U1" "$PASS" remember
assert_header set-cookie '_marginalia_web_user_remember_me=.*[Mm]ax-[Aa]ge=1209600' "auth: the remember-me cookie lasts 14 days (1209600 s)"
# test "redirects to settings when user is already logged in"
login "$U1" "$PASS" remember
assert_redirect_to "/users/settings" "auth: logging in while already logged in goes to /users/settings"
# test "writes a cookie if remember_me was set in previous session"
skip "auth: remember-me persists across a re-login without the flag (needs the server-side session to carry user_remember_me; assert once the session store is in)"

# logout_user/1
# test "erases session and cookies"
new_visitor auth-logout
login "$U1" "$PASS" remember
logout
assert_header set-cookie '_marginalia_web_user_remember_me=.*([Mm]ax-[Aa]ge=0|[Ee]xpires=)' "auth: log-out expires the remember-me cookie"
assert_redirect_to "/" "auth: log-out redirects to /"
get /users/settings
assert_redirect_to "/users/log-in" "auth: the token is dead after log-out"
# test "broadcasts to the given live_socket_id"
skip "auth: log-out disconnects open sockets (no sockets in this design: pages poll; nothing to broadcast to)"
# test "works even if user is already logged out"
new_visitor auth-logout-anon
logout
assert_redirect_to "/" "auth: log-out when already logged out redirects to /"

# fetch_current_scope_for_user/2
# test "authenticates user from session"
new_visitor auth-scope
login "$U1" "$PASS"
get /users/settings
assert_contains "$U1" "auth: the session token authenticates the user"
# test "authenticates user from cookies"
login "$U1" "$PASS" remember
rm_cookie_jar="$T/jar.scope-cookie"; grep -v '_marginalia_key' "$JAR" > "$rm_cookie_jar"; JAR="$rm_cookie_jar"
get /users/settings
assert_contains "$U1" "auth: the remember-me cookie alone authenticates the user"
# test "does not authenticate if data is missing"
new_visitor auth-missing
get /users/log-in
assert_not_contains "$U1" "auth: no cookie, no user"
# test "reissues a new token after a few days and refreshes cookie"
skip "auth: a 10-day-old token is reissued with a refreshed cookie (needs clock control)"

# on_mount :mount_current_scope / :require_authenticated / :require_sudo_mode
# test "assigns current_scope based on a valid user_token" / nil for invalid / nil for none
new_visitor auth-badtoken
_curl GET /users/log-in -H 'cookie: _marginalia_key=invalid_token'
assert_status 200 "auth: an invalid session cookie is treated as no session, not an error"
assert_not_contains "$U1" "auth: an invalid session cookie shows no user"
# test "authenticates current_scope based on a valid user_token" / "redirects to login page if there isn't a valid user_token" (x2)
new_visitor auth-require
get /users/settings
assert_redirect_to "/users/log-in" "auth: a protected page without a session redirects to /users/log-in"
_curl GET /users/settings -H 'cookie: _marginalia_key=invalid_token'
assert_redirect_to "/users/log-in" "auth: a protected page with an invalid token redirects to /users/log-in"
# test "allows users that have authenticated in the last 10 minutes" / "redirects when authentication is too old"
login "$U1" "$PASS"
get /users/settings
assert_status 200 "auth: a fresh login is inside the 10-minute sudo window"
skip "auth: a login older than 10 minutes is sent back to /users/log-in (needs clock control)"

# require_authenticated_user/2
# test "redirects if user is not authenticated"
new_visitor auth-plug
get /users/settings
assert_redirect_to "/users/log-in" "auth: unauthenticated redirects to /users/log-in"
get /users/log-in
assert_contains "You must log in to access this page." "auth: the flash is You must log in to access this page."
# test "stores the path to redirect to on GET"
new_visitor auth-return2
get "/users/settings?bar=baz"
login "$U1" "$PASS"
assert_redirect_to "/users/settings?bar=baz" "auth: the return-to keeps the query string (/users/settings?bar=baz)"
new_visitor auth-return3
get /users/log-in
post /users/update-password "user%5Bpassword%5D=x"
assert_redirect_to "/users/log-in" "auth: a POST by a visitor is sent to log in"
login "$U1" "$PASS"
assert_redirect_to "/" "auth: a POST does not store a return-to"
# test "does not redirect if user is authenticated"
get /users/settings
assert_status 200 "auth: an authenticated user is not redirected"

# disconnect_sessions/1
# test "broadcasts disconnect messages for each token"
skip "auth: password change disconnects other sessions' sockets (no sockets; other sessions' tokens are deleted instead, assert via a second jar once update-password lands)"
