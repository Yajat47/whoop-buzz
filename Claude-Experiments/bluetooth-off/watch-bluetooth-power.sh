#!/bin/zsh
# Passive watcher: timestamps every Bluetooth power change, lock and screen
# event the iPhone posts, so a Bluetooth drop can be lined up against the
# buzz app's log. Observes only; sends nothing to the phone or the band.
# Usage: ./watch-bluetooth-power.sh [minutes, default 25]   (phone on USB, unlocked once)
set -u
DEVICE="${PHONE_UDID:?Set PHONE_UDID to your iPhone UDID (xcrun devicectl list devices)}"
MINUTES="${1:-25}"
SECONDS_TOTAL=$((MINUTES * 60))
OUT="$(cd "$(dirname "$0")" && pwd)/power-watch-$(date +%Y%m%d-%H%M%S).log"

echo "Watching for $MINUTES min -> $OUT"
xcrun devicectl device notification observe --device "$DEVICE" \
  --name com.apple.bluetooth.power-changed \
  --name com.apple.springboard.lockstate \
  --name com.apple.springboard.hasBlankedScreen \
  --name com.apple.system.lowpowermode \
  --session-timeout "$SECONDS_TOTAL" --timeout $((SECONDS_TOTAL + 60)) 2>&1 \
  | while IFS= read -r line; do
      print -r -- "$(date '+%H:%M:%S')  $line" | tee -a "$OUT"
    done
