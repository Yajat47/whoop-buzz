#!/bin/zsh
# Read-only check of the Shortcuts "Notification" automation trigger in the
# OS build Xcode copied from the owner's iPhone (iOS DeviceSupport symbols).
# Touches no device and sends no Bluetooth. Usage: ./check-notification-trigger.sh
set -u
SUPPORT="${1:-$HOME/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,4 27.0 (24A437)}"
BIN="$SUPPORT/arm64e/Symbols/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit"
[ -f "$BIN" ] || { echo "WorkflowKit not found under: $SUPPORT"; exit 1; }

echo "Device OS symbols: $SUPPORT"
echo "WorkflowKit sha256: $(shasum -a 256 "$BIN" | cut -d' ' -f1)"

echo "\n== Automation trigger classes in this build"
nm -arch arm64e "$BIN" 2>/dev/null | grep -o '_OBJC_CLASS_\$_WF[A-Za-z0-9]*Trigger$' \
  | sed 's/_OBJC_CLASS_\$_//' | sort -u | tr '\n' ' '; echo

echo "\n== WFNotificationTrigger methods"
nm -arch arm64e "$BIN" 2>/dev/null | grep -E ' [+-]\[WFNotificationTrigger' | cut -c20-

# First instruction of each gate is 'mov w0, #N' followed by ret: N is the return value.
echo "\n== Gates (return value = the #0x… constant)"
for sym in '+[WFNotificationTrigger isAllowedToRunAutomatically]' \
           '+[WFTrigger isAllowedToRunAutomatically]' \
           '+[WFTrigger isSupportedOnThisDevice]'; do
  echo "$sym"
  otool -arch arm64e -tV -p "$sym" "$BIN" 2>/dev/null | grep -A2 -F "$sym:" | sed -n '2,3p'
done
echo "WFNotificationTrigger overrides isSupportedOnThisDevice: $(nm -arch arm64e "$BIN" 2>/dev/null \
  | grep -c '+\[WFNotificationTrigger isSupportedOnThisDevice\]')  (0 = inherits WFTrigger's value)"

echo "\n== Reasons the OS logs for not firing"
strings -a -arch arm64e "$BIN" | grep -E 'Notification trigger not firing|hydrate UserNotificationEntity|hydration returned empty' | sort -u

echo "\n== Feature flag named beside the trigger definition"
strings -a -arch arm64e "$BIN" | grep -x -E 'new_system_automations|When a notification is received' | sort -u
