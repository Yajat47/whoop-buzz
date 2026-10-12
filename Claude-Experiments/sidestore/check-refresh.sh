#!/bin/zsh
# Read-only: show SideStore's recent refresh runs from its own log on the
# iPhone, so a scheduled refresh can be confirmed from the Mac.
# Times are the phone's local time; expiry dates are printed in UTC.
# Usage: ./check-refresh.sh        (phone on USB, unlocked once since restart)
set -u
DEVICE="${PHONE_UDID:?Set PHONE_UDID to your iPhone UDID (xcrun devicectl list devices)}"
SIDESTORE="${SIDESTORE_BUNDLE:?Set SIDESTORE_BUNDLE, for example com.SideStore.SideStore.YOURTEAMID}"
TMP="$(mktemp -d /tmp/claude-sidestore-check.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

logs=$(xcrun devicectl device info files --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$SIDESTORE" \
  --subdirectory Documents/ConsoleLogs 2>/dev/null \
  | grep -o 'console_[0-9_]*\.log' | sort -u | tail -5)
if [ -z "$logs" ]; then
  echo "Cannot read SideStore's logs. Is the phone plugged in and unlocked?"
  exit 1
fi

for log in ${(f)logs}; do
  xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$SIDESTORE" \
    --source "Documents/ConsoleLogs/$log" --destination "$TMP/$log" >/dev/null 2>&1
done

# One line per event: run start, each new expiry, each install result, run end.
cat "$TMP"/console_*.log 2>/dev/null \
  | grep -E '^20[0-9-]+T' \
  | grep -E 'RefreshAppsOperation\] execute\(\) (started|took)|Finished refreshing with results|prepared successfully for .*expiration|performOperation: completed successfully|[Ee]rror' \
  | grep -v -i -E 'password|token|cookie|UNErrorDomain|Error while fetching installed apps|error: nil' \
  | sed -E 's/ \[D\]: / /; s/\[FetchProvisioningProfiles\] Main profile prepared successfully for /new expiry: /; s/\[AppManager\] performOperation: completed successfully. progress was reset for installedApp: /refreshed: /' \
  | cut -c1-170 | tail -24
