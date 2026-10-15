#!/bin/bash
# build.sh: temper build -b blimp -w temper, then out/marginalia.blimp =
#   generated server/main.blimp + the _connected.blimp of every library the
#   server imports (the backend splices only the built library's own) +
#   entry.blimp; then static/js/app.js. Exits non-zero on any failure.
#
# Overridable: TEMPER (the CLI), BLIMP_BIN (a directory holding the 115 blimp),
# JAVA_HOME.
set -u
cd "$(dirname "$0")" || exit 1

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
BLIMP_BIN="${BLIMP_BIN:-/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin}"
export PATH="$JAVA_HOME/bin:$BLIMP_BIN:$PATH"
TEMPER="${TEMPER:-/Users/bg/code/temper-blimp-115/temper/cli/build/install/temper/bin/temper}"

fail() { echo "build.sh: $*" >&2; exit 1; }

[ -x "$TEMPER" ] || fail "no temper CLI at $TEMPER (set TEMPER=)"
[ -x "$BLIMP_BIN/blimp" ] || fail "no blimp in $BLIMP_BIN (set BLIMP_BIN=)"

LOG="$(mktemp "${TMPDIR:-/tmp}/marginalia-build.XXXXXX")"
trap 'rm -f "$LOG"' EXIT

echo "== temper build -b blimp -w temper"
"$TEMPER" build -b blimp -w temper > "$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ] || grep -q "Build failed" "$LOG"; then
  cat "$LOG" >&2
  bad="$(grep -o '\-work/[A-Za-z0-9_]*/' "$LOG" | sort -u | sed 's|-work/||; s|/||' | tr '\n' ' ')"
  fail "temper build failed (exit $rc); libraries with errors: ${bad:-none named}"
fi
tail -5 "$LOG"

GEN=temper/temper.out/blimp/server/main.blimp
[ -f "$GEN" ] || fail "no $GEN after the build"

# Libraries the server imports, transitively: import("lib/src") in the sources.
libs="server"
queue="server"
while [ -n "$queue" ]; do
  next=""
  for l in $queue; do
    for d in $(cat temper/"$l"/src/*.temper.md 2>/dev/null | grep -o 'import("[A-Za-z0-9_]*/src")' | sed 's/import("//; s|/src")||' | sort -u); do
      case " $libs " in *" $d "*) ;; *) libs="$libs $d"; next="$next $d" ;; esac
    done
  done
  queue="$next"
done

mkdir -p out
{
  cat "$GEN"
  for l in $libs; do
    f=temper/$l/src/_connected.blimp
    [ -f "$f" ] || continue
    echo
    echo "# ---- $f ----"
    cat "$f"
  done
  echo
  cat entry.blimp
} > out/marginalia.blimp || fail "could not write out/marginalia.blimp"

echo "== static/js/bundle.sh"
bytes="$(sh static/js/bundle.sh)" || fail "static/js/bundle.sh failed"
echo "static/js/app.js: $bytes bytes"

gen_lines="$(wc -l < "$GEN" | tr -d ' ')"
hand_lines="$(wc -l < entry.blimp | tr -d ' ')"
conn_lines=0
for l in $libs; do
  f=temper/$l/src/_connected.blimp
  [ -f "$f" ] && conn_lines=$((conn_lines + $(wc -l < "$f" | tr -d ' ')))
done
total="$(wc -l < out/marginalia.blimp | tr -d ' ')"
echo "== out/marginalia.blimp: $total lines"
echo "   generated:                 $gen_lines"
echo "   hand-written _connected:   $conn_lines  (libraries: $libs)"
echo "   hand-written entry.blimp:  $hand_lines"
