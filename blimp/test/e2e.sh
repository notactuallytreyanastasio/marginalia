#!/usr/bin/env bash
# e2e.sh: start fake_llm and the app on free ports with a throwaway database, run
# every test/e2e/*.sh in name order, print "N passed, M failed", clean up.
#
#   ./blimp/test/e2e.sh                                  # APP=blimp/out/marginalia.blimp
#   APP=blimp/test/stub_app.blimp ./blimp/test/e2e.sh    # the stand-in
#   E2E_KEEP=1 ./blimp/test/e2e.sh                       # keep the temp dir (logs, sqlite)
#   ONLY=20_works.sh ./blimp/test/e2e.sh                 # run one file
#
# Exit status: 0 when nothing failed, 1 on a failed assertion, a test file that
# died, or a server that did not come up (2 for the last).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"   # the worktree root: APP and the stub's css path are relative to it
cd "$ROOT" || exit 2

BLIMP="${BLIMP:-/Users/bg/code/temper-blimp-114/blimp/chunks/lang/zig-out/bin/blimp}"
[ -x "$BLIMP" ] || BLIMP="$(command -v blimp)"
[ -x "$BLIMP" ] || { echo "no blimp interpreter (set BLIMP=)" >&2; exit 2; }
APP="${APP:-blimp/out/marginalia.blimp}"
[ -f "$APP" ] || { echo "app not found: $APP (build it, or APP=blimp/test/stub_app.blimp)" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/marginalia-e2e.XXXXXX")"
FAKE_PID=""; APP_PID=""

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null && return
  local p
  for p in $(jot -r 40 20000 60000); do lsof -i ":$p" >/dev/null 2>&1 || { echo "$p"; return; }; done
}

# kill a server, its children (the app forks per request) and anything still listening on its port
reap_server() { # PID PORT
  local pid="$1" port="$2" l
  if [ -n "$pid" ]; then
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
  fi
  sleep 0.2
  for l in $(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null); do kill -9 "$l" 2>/dev/null; done
}

cleanup() {
  reap_server "$APP_PID" "${PORT:-0}"
  reap_server "$FAKE_PID" "${FAKE_PORT:-0}"
  if [ "${E2E_KEEP:-}" = 1 ]; then echo "# kept $TMP"; else rm -rf "$TMP"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

wait_port() { # URL SECONDS NAME LOG PID
  local url="$1" secs="$2" name="$3" log="$4" pid="$5" i=0 n=$(($2 * 10))
  while [ "$i" -lt "$n" ]; do
    # any HTTP answer at all (even a 404) means the port is up
    curl -s -o /dev/null --max-time 2 "$url" && return 0
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "FATAL: $name exited before answering on $url" >&2; tail -20 "$log" >&2; return 1
    fi
    sleep 0.1; i=$((i + 1))
  done
  echo "FATAL: $name did not answer on $url within $secs s" >&2; tail -20 "$log" >&2
  return 1
}

FAKE_PORT="$(free_port)"
PORT="$(free_port)"
while [ "$PORT" = "$FAKE_PORT" ]; do PORT="$(free_port)"; done

# --- fake llm -----------------------------------------------------------
E2E_LLM_LOG="$TMP/fake_llm.log"
"$BLIMP" "$HERE/fake_llm.blimp" "$FAKE_PORT" "$HERE/fixtures/llm" > "$E2E_LLM_LOG" 2>&1 &
FAKE_PID=$!
wait_port "http://127.0.0.1:$FAKE_PORT/health" 20 fake_llm "$E2E_LLM_LOG" "$FAKE_PID" || exit 2

# --- app ------------------------------------------------------------------
export MARGINALIA_DB="$TMP/test.sqlite3"
export PORT
export MARGINALIA_LLM_ENDPOINT="http://127.0.0.1:$FAKE_PORT/chat/completions"
export MARGINALIA_LLM_PROVIDER=deepseek
export DEEPSEEK_API_KEY=test-key
export MARGINALIA_OWNER_EMAIL=owner@example.com
export MARGINALIA_SECRET='test-secret-32-bytes-long-string!!'
export MARGINALIA_LLM_BACKOFF_MS="${MARGINALIA_LLM_BACKOFF_MS:-0}"   # optional: the app may ignore it

APP_LOG="$TMP/app.log"
"$BLIMP" "$APP" > "$APP_LOG" 2>&1 &
APP_PID=$!
wait_port "http://127.0.0.1:$PORT/" 20 app "$APP_LOG" "$APP_PID" || exit 2
echo "# app $APP on :$PORT, fake_llm on :$FAKE_PORT, db $MARGINALIA_DB"

# --- run the files ----------------------------------------------------------
export E2E_BASE="http://127.0.0.1:$PORT" E2E_FAKE="http://127.0.0.1:$FAKE_PORT" E2E_LLM_LOG
pass=0; fail=0; skipped=0; files=0; died=0

for f in "$HERE"/e2e/*.sh; do
  name="$(basename "$f")"
  [ -n "${ONLY:-}" ] && [ "$name" != "$ONLY" ] && continue
  files=$((files + 1))
  echo "# $name"
  out="$TMP/out.$name"
  bash "$f" > "$out" 2>&1
  rc=$?
  cat "$out"
  p=$(grep -c '^ok ' "$out"); s=$(grep -c '^ok .*# SKIP' "$out"); n=$(grep -c '^not ok ' "$out")
  pass=$((pass + p - s)); skipped=$((skipped + s)); fail=$((fail + n))
  if [ "$rc" -ne 0 ]; then
    died=$((died + 1)); fail=$((fail + 1))
    echo "not ok - $name exited with status $rc"
  fi
done

if [ "$files" -eq 0 ]; then echo "no test files ran" >&2; exit 2; fi

echo
echo "$pass passed, $fail failed"
echo "($skipped skipped, $files files)"
if [ "$fail" -gt 0 ]; then
  echo "--- app log (tail) ---"; tail -15 "$APP_LOG"
  echo "--- fake_llm log (tail) ---"; tail -10 "$E2E_LLM_LOG"
  exit 1
fi
exit 0
