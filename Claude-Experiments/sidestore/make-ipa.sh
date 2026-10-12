#!/bin/zsh
# Build WHOOP Buzz as an .ipa for SideStore. With --push, also copy it into
# SideStore's folder on the iPhone. The install itself is done on the phone:
# SideStore > My Apps > + > On My iPhone > SideStore.
# Usage: ./make-ipa.sh [--push] [project-dir]   (default project: ../../WhoopBuzz)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${PHONE_UDID:-}"
SIDESTORE="${SIDESTORE_BUNDLE:-}"
PUSH=0
if [ "${1:-}" = "--push" ]; then PUSH=1; shift; fi
PROJECT_DIR="$(cd "${1:-$HERE/../../WhoopBuzz}" && pwd)"
NAME="WhoopBuzz-$(date +%Y%m%d-%H%M).ipa"
STAGE="$(mktemp -d /tmp/claude-ipa.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# Release build: one executable, no debug dylib for SideStore to re-sign.
if ! xcodebuild -project "$PROJECT_DIR/WhoopBuzz.xcodeproj" -scheme WhoopBuzz \
     -sdk iphoneos -configuration Release -destination generic/platform=iOS \
     -derivedDataPath "$HERE/Build" build > "$HERE/make-ipa-build.log" 2>&1; then
  echo "Build failed. Last lines of $HERE/make-ipa-build.log:"
  tail -15 "$HERE/make-ipa-build.log"
  exit 1
fi

mkdir -p "$STAGE/Payload"
cp -R "$HERE/Build/Build/Products/Release-iphoneos/WhoopBuzz.app" "$STAGE/Payload/"
(cd "$STAGE" && zip -qry "$HERE/$NAME" Payload)
echo "Built $HERE/$NAME from $PROJECT_DIR"

if [ "$PUSH" = 1 ]; then
  : "${DEVICE:?Set PHONE_UDID to your iPhone UDID}" "${SIDESTORE:?Set SIDESTORE_BUNDLE to SideStore's bundle ID}"
  xcrun devicectl device copy to --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$SIDESTORE" \
    --source "$HERE/$NAME" --destination "Documents/$NAME" >/dev/null
  echo "Copied to the phone. In SideStore: My Apps > + > On My iPhone > SideStore > $NAME"
fi
