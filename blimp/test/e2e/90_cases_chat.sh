#!/usr/bin/env bash
# 90_cases_chat.sh: asking the case chat a question, which reaches the (fake) model.
# Runs only when "90_cases_chat.sh" is listed in test/e2e/IMPLEMENTED.
#
# Source tests (notes/tests.md): case_read_test, describe "the chat about the case":
#   "asking keeps the question and does not hang" (and its success path, which the Elixir test could
#   not reach because it had no model), and the case chat as the case-chat section of
#   notes/domain-accounts-links-stacks.md specifies it.
#
# These asks are a file of their own, after 60_cuts.sh, because 60_cuts.sh asserts the fake model's
# request count from zero (llm_calls == 0, == 1, == 2) and a model call made by an earlier file would
# move it. The case is placed again here (the inserts are OR IGNORE), so the file stands alone.
#
# The fake picks its reply by a needle in the last user message or a system message: FAKE_CHAT gives
# the canned chat answer, FAKE_LLM_500 a 500 (the client tries three times, then gives up).
. "$(dirname "$0")/../lib.sh"
skip_unless_implemented
. "$(dirname "$0")/../cases_fixtures.sh"

if ! command -v sqlite3 >/dev/null 2>&1 || [ -z "${MARGINALIA_DB:-}" ]; then
  skip "case chat: no sqlite3 or no MARGINALIA_DB, the fixtures cannot be placed"
  exit 0
fi

new_visitor setup
cases_owner
cases_some_v_case

new_visitor chatter
get /cases/some-v-case/read
evm toggle_chat '{}' /cases/some-v-case/read
assert_contains "lc-panel" "chat: the panel is open"

LLM_BEFORE="$(llm_calls)"
evm chat_send '{"message":"Who conceded what? FAKE_CHAT"}' /cases/some-v-case/read
assert_contains "Who conceded what? FAKE_CHAT" "chat: asking keeps the question"
assert_contains "This is the canned chat answer." "chat: and shows the reply"
assert_contains "lc-turn user" "chat: the question is the reader's turn"
assert_contains "lc-turn assistant" "chat: and the answer is the reader's"
assert_not_contains "lc-thinking" "chat: and does not hang"
assert_not_contains 'class="lc-hint"' "chat: the hint is gone once there is a conversation"
assert_eq "$FLASH_ERR" "" "chat: with no error"
assert_eq "$(( $(llm_calls) - LLM_BEFORE ))" "1" "chat: one model call"
assert_llm_log_contains "chat/completions" "chat: and it reached the model"

# the conversation lives in the session: it survives a move to another document of the case, and a reload
get /cases/some-v-case/read/s2di
assert_contains "This is the canned chat answer." "chat: the conversation survives a move to another document of the case"
get /cases/some-v-case/read
assert_contains "Who conceded what? FAKE_CHAT" "chat: and a reload"

# a note's connection goes into the question and is let go after it
evm cite_edge "{\"edge\":\"$EDGE_TENSION\"}" /cases/some-v-case/read
assert_contains "lc-cited" "chat: a cited connection is in the panel"
evm chat_send '{"message":"Why do they part? FAKE_CHAT"}' /cases/some-v-case/read
assert_not_contains "lc-cited" "chat: and is let go once asked"
assert_contains "Why do they part? FAKE_CHAT" "chat: the second question is under the first"
assert_eq "$(( $(llm_calls) - LLM_BEFORE ))" "2" "chat: a second model call"

# the model fails: the question is kept, the failure is said, the page does not hang
evm chat_send '{"message":"FAKE_LLM_500 does this fail?"}' /cases/some-v-case/read
assert_contains "does this fail?" "chat: asking keeps the question when the model fails"
case "$FLASH_ERR" in "That did not go through: "*) _ok "chat: and says so" ;; *) _bad "chat: and says so" "flash.error = '$FLASH_ERR'" ;; esac
assert_contains "lc-panel" "chat: the panel is still open"

# an empty question asks nothing
CALLS="$(llm_calls)"
evm chat_send '{"message":"   "}' /cases/some-v-case/read
assert_eq "$(llm_calls)" "$CALLS" "chat: an empty question asks nothing"
