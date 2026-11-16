#!/usr/bin/env bash
# Build this fork and install it over /Applications/FineTune.app.
# Version is pinned to the live upstream release so Sparkle sees no update,
# but a genuine newer release still shows on a manual check. Bump both on rebase.
set -euo pipefail

VERSION="${VERSION:-1.9.0}"
BUILD="${BUILD:-38}"
IDENTITY="Developer ID Application: Noah Baxter (KUP5WU7WPC)"
TEAM=KUP5WU7WPC

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$REPO/build/Build/Products/Release/FineTune.app"

rm -rf "$REPO/build/Build/Products/Release"
xcodebuild -project "$REPO/FineTune.xcodeproj" -scheme FineTune -configuration Release \
  -derivedDataPath "$REPO/build" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" \
  build

# Ad-hoc signing leaves Sparkle.framework on its own team ID and dyld refuses to load it.
codesign --verify --deep --strict "$APP"

osascript -e 'quit app "FineTune"' 2>/dev/null || true
sleep 2
rm -rf /Applications/FineTune.app
cp -R "$APP" /Applications/FineTune.app
open -a /Applications/FineTune.app

echo "installed FineTune $VERSION ($BUILD) from $(git -C "$REPO" rev-parse --short HEAD)"
