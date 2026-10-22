#!/bin/zsh
# Captures the menu bar panel, the main window and the widgets for each demo scenario.
#   scripts/showcase.sh <out-dir> [scenario …]     (default: every scenario)
#   FLEET=1 scripts/showcase.sh <out-dir>   three simulated printers instead of one
#   PAGE=settings scripts/showcase.sh <out-dir> printing   opens a window page (overview, filament, history, settings, about, add)
# Needs Screen Recording permission for the terminal that runs it.
set -euo pipefail

ROOT=${0:A:h:h}
OUT=${1:?usage: scripts/showcase.sh <out-dir> [scenario …]}
shift
SCENARIOS=("$@")
(( ${#SCENARIOS} )) || SCENARIOS=(printing preparing paused finished failed idle offline unconfigured)
BIN="$ROOT/build/App.noindex/Bambu Bar.app/Contents/MacOS/Bambu Bar"
mkdir -p "$OUT"
for scenario in $SCENARIOS; do
  pkill -f "$BIN" 2>/dev/null && sleep 0.5 || true
  rm -f "$OUT/windows.txt"
  "$BIN" --demo "$scenario" --showcase "$OUT" ${PAGE:+--page} ${PAGE:+$PAGE} ${FLEET:+--fleet} >/dev/null 2>&1 &
  for _ in {1..40}; do [[ -f "$OUT/windows.txt" ]] && break; sleep 0.25; done
  sleep ${SETTLE:-1.5}
  while read -r name id; do
    screencapture -x -o -l "$id" "$OUT/$scenario-$name${PAGE:+-$PAGE}.png"
  done < "$OUT/windows.txt"
  echo "==> $scenario"
done
pkill -f "$BIN" 2>/dev/null || true
