#!/bin/bash
# run.sh: serve out/marginalia.blimp from blimp/, so static/ resolves.
# PORT (default 4000), LOG_DIR (default log), STATIC_ROOT (default static).
cd "$(dirname "$0")" || exit 1
BLIMP_BIN="${BLIMP_BIN:-/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin}"
export PATH="$BLIMP_BIN:$PATH"
[ -f out/marginalia.blimp ] || { echo "run.sh: out/marginalia.blimp is missing; run ./build.sh" >&2; exit 1; }
exec blimp out/marginalia.blimp
