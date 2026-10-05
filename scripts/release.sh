#!/usr/bin/env bash
#
# Memo release helper.
#
# Builds a Release archive, exports Memo.app, packages it into a .dmg
# (via create-dmg).
#
# Requires: create-dmg (brew install create-dmg)
#
# This script does NOT push to git, create a GitHub release, or upload
# anything — it only prepares local files and prints the exact commands
# to finish the release yourself.
#
# Usage:
#   scripts/release.sh                    # use version/build from the Xcode project
#   scripts/release.sh --version 1.1 --build 3

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/Memo Todo App.xcodeproj"
SCHEME="MyApp"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/Memo.xcarchive"

VERSION=""
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD_NUMBER="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

echo "==> Reading build settings"
SETTINGS=$(xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)

if [[ -z "$VERSION" ]]; then
  VERSION=$(echo "$SETTINGS" | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER=$(echo "$SETTINGS" | awk -F' = ' '/ CURRENT_PROJECT_VERSION /{print $2; exit}')
fi

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Could not determine version/build number from the project." >&2
  echo "Pass them explicitly: scripts/release.sh --version 1.1 --build 3" >&2
  exit 1
fi

echo "==> Releasing Memo v$VERSION (build $BUILD_NUMBER)"

echo "==> Cleaning old build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release configuration, ad-hoc signed)"
if ! xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE_PATH" archive; then
  echo "Archive failed." >&2
  exit 1
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Memo.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive did not produce Memo.app at expected path: $APP_PATH" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not found. Install it with: brew install create-dmg" >&2
  exit 1
fi

DMG_NAME="Memo-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "==> Building DMG"
rm -f "$DMG_PATH"
create-dmg \
  --volname "Memo $VERSION" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Memo.app" 175 190 \
  --app-drop-link 425 190 \
  "$DMG_PATH" \
  "$APP_PATH" \
  || {
    # create-dmg exits non-zero even on success in some environments (e.g. AppleScript
    # warnings when Finder can't set icon positions); treat it as fatal only if no DMG appeared.
    if [[ ! -f "$DMG_PATH" ]]; then
      echo "create-dmg failed and no DMG was produced." >&2
      exit 1
    fi
    echo "create-dmg reported a non-fatal warning; DMG was created at $DMG_PATH" >&2
  }

echo ""
echo "==> Build artifact: $DMG_PATH"
echo ""
echo "==> Next steps:"
echo "1. Tag and push: git tag v$VERSION && git push origin v$VERSION"
echo "2. Create the GitHub release with the DMG attached:"
echo "     gh release create v$VERSION \"$DMG_PATH\" --title \"Memo $VERSION\" --generate-notes"
echo ""
echo "Note: this build is ad-hoc signed (no Apple Developer Program membership)."
echo "First-time installers need to approve it once via System Settings ->"
echo "Privacy & Security -> Open Anyway."
