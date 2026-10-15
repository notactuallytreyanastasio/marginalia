#!/bin/sh
# Concatenate vendor/topbar.js + blimp.js + hooks/*.js into app.js.
# Order matters: blimp.js defines window.Blimp, the hooks register on it, and
# it boots on a microtask / DOMContentLoaded, after every hook has registered.
# Prints the size of app.js in bytes.
set -eu
cd "$(dirname "$0")"
out=app.js
: > "$out.tmp"
for f in vendor/topbar.js blimp.js hooks/*.js; do
  printf '/* ---- %s ---- */\n' "$f" >> "$out.tmp"
  cat "$f" >> "$out.tmp"
  printf '\n' >> "$out.tmp"
done
mv "$out.tmp" "$out"
wc -c < "$out" | tr -d ' '
