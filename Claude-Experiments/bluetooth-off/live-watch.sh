#!/bin/zsh
# Passive live watch for one Shortcuts test. Prints, with Mac clock times:
#   PHONE  each Bluetooth power change, lock and screen event the iPhone posts
#   APP    each new line the buzz app adds to its saved log (phone clock)
# Observes and copies only; sends nothing to the band.
# Usage: ./live-watch.sh [minutes, default 25]   (phone on USB)
set -u
DEVICE="${PHONE_UDID:?Set PHONE_UDID to your iPhone UDID (xcrun devicectl list devices)}"
BUNDLE="${WHOOP_BUZZ_BUNDLE:?Set WHOOP_BUZZ_BUNDLE to the app bundle ID on your phone}"
MINUTES="${1:-25}"
TOTAL=$((MINUTES * 60))
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/live-watch-$(date +%Y%m%d-%H%M%S).log"
TMP="$(mktemp -d /tmp/claude-live-watch.XXXXXX)"
trap 'kill $OBSERVER 2>/dev/null; rm -rf "$TMP"' EXIT

emit() { print -r -- "$(date '+%H:%M:%S')  $1" | tee -a "$OUT"; }

xcrun devicectl device notification observe --device "$DEVICE" \
  --name com.apple.bluetooth.power-changed \
  --name com.apple.springboard.lockstate \
  --name com.apple.springboard.hasBlankedScreen \
  --session-timeout "$TOTAL" --timeout $((TOTAL + 60)) 2>&1 \
  | grep --line-buffered -v -E 'seconds remaining|^$' \
  | while IFS= read -r line; do emit "PHONE  $line"; done &
OBSERVER=$!

touch "$TMP/seen"
END=$(( $(date +%s) + TOTAL ))
FIRST=1
while [ "$(date +%s)" -lt "$END" ]; do
  if xcrun devicectl device copy from --device "$DEVICE" \
       --domain-type appDataContainer --domain-identifier "$BUNDLE" \
       --source "Library/Preferences/$BUNDLE.plist" \
       --destination "$TMP/prefs.plist" >/dev/null 2>&1; then
    plutil -extract 'whoop\.researchLog' json -o - "$TMP/prefs.plist" 2>/dev/null \
      | python3 -I -c 'import json,sys; [print(l) for l in reversed(json.load(sys.stdin))]' \
      > "$TMP/now" 2>/dev/null
    if [ "$FIRST" = 1 ]; then
      FIRST=0                       # existing lines are history, not news
    else
      grep -F -x -v -f "$TMP/seen" "$TMP/now" | while IFS= read -r line; do emit "APP    $line"; done
    fi
    cp "$TMP/now" "$TMP/seen"
    FAILS=0
  else
    FAILS=$(( ${FAILS:-0} + 1 ))
    [ "$FAILS" = 3 ] && emit "WATCH  cannot reach the phone (unplugged or locked since restart?)"
  fi
  sleep 6
done
emit "WATCH  finished after $MINUTES minutes"
