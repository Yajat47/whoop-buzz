#!/bin/zsh
# Read-only: copy the buzz app's saved research log off the iPhone and print it.
# Proof for the live test: each Shortcuts-started buzz leaves a timestamped
# "Shortcuts requested one buzz." line. Sends nothing to the band.
# Usage: ./pull-buzz-log.sh [bundle-id]
set -u
DEVICE="${PHONE_UDID:?Set PHONE_UDID to your iPhone UDID (xcrun devicectl list devices)}"
BUNDLE="${1:-${WHOOP_BUZZ_BUNDLE:?Set WHOOP_BUZZ_BUNDLE to the app bundle ID on your phone}}"
OUT="$(cd "$(dirname "$0")" && pwd)/device-logs"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "Library/Preferences/$BUNDLE.plist" \
  --destination "$OUT/$STAMP.plist" >/dev/null 2>"$OUT/$STAMP.err" \
  || { echo "Copy failed (phone unplugged or locked since boot?):"; cat "$OUT/$STAMP.err"; exit 1; }
rm -f "$OUT/$STAMP.err"

echo "Pulled at $(date '+%H:%M:%S') -> $OUT/$STAMP.plist  (newest line first)"
plutil -extract 'whoop\.researchLog' json -o - "$OUT/$STAMP.plist" \
  | python3 -I -c '
import json, sys
lines = json.load(sys.stdin)
for line in lines:
    print(("  >> " if "Shortcuts" in line else "     ") + line)
runs = sum("Shortcuts requested" in l for l in lines)
ok = sum("Shortcuts" in l and "confirmed" in l for l in lines)
bad = sum("Shortcuts test failed" in l for l in lines)
print(f"\nShortcuts-started buzzes in the last {len(lines)} lines: {runs} requested, {ok} confirmed, {bad} failed")
'
