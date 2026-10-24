#!/bin/bash
# run.sh: serve out/marginalia.blimp from blimp/, so static/ resolves.
# PORT (default 4000), LOG_DIR (default log), STATIC_ROOT (default static).
#
# The model key comes from the environment (DEEPSEEK_API_KEY, or
# OPENAI_API_KEY with MARGINALIA_LLM_PROVIDER=openai), as Phoenix's
# config/runtime.exs reads it. Phoenix gets it from a gitignored .env at the
# repository root; so does this script: ENV_FILE (default ../.env) is sourced
# when it exists. A worktree has no .env of its own; link or copy the main
# checkout's.
cd "$(dirname "$0")" || exit 1
ROOT="$(cd .. && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi
case "${MARGINALIA_LLM_PROVIDER:-deepseek}" in
  openai) [ -n "${OPENAI_API_KEY:-}" ] || echo "run.sh: OPENAI_API_KEY is not set (no $ENV_FILE?); model calls will fail" >&2 ;;
  *)      [ -n "${DEEPSEEK_API_KEY:-}" ] || echo "run.sh: DEEPSEEK_API_KEY is not set (no $ENV_FILE?); model calls will fail" >&2 ;;
esac
BLIMP_BIN="${BLIMP_BIN:-/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin}"
export PATH="$BLIMP_BIN:$PATH"
[ -f out/marginalia.blimp ] || { echo "run.sh: out/marginalia.blimp is missing; run ./build.sh" >&2; exit 1; }
exec blimp out/marginalia.blimp
