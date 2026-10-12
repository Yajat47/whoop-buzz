#!/bin/zsh
# Battery study report. Copies the buzz app's saved battery readings off the
# iPhone (read-only) and runs battery_report.py on them.
# Needs the build with the "Battery study" section, with tap listening on.
# Usage: ./battery-report.sh            pull from the phone on USB
#        ./battery-report.sh FILE.plist analyse a saved copy instead
set -u
DEVICE="${PHONE_UDID:?Set PHONE_UDID to your iPhone UDID (xcrun devicectl list devices)}"
BUNDLE="${WHOOP_BUZZ_BUNDLE:?Set WHOOP_BUZZ_BUNDLE to the app bundle ID on your phone}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/device-logs"

if [ $# -ge 1 ]; then
  PLIST="$1"
else
  PLIST="$HERE/device-logs/battery-$(date +%Y%m%d-%H%M%S).plist"
  if ! xcrun devicectl device copy from --device "$DEVICE" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE" \
        --source "Library/Preferences/$BUNDLE.plist" --destination "$PLIST" >/dev/null 2>&1; then
    echo "Could not copy from the phone. Is it plugged in and unlocked?"
    exit 1
  fi
fi

python3 -I "$HERE/battery_report.py" "$PLIST"
