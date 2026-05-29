#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$ROOT_DIR/DSkiller.app"
DMG_PATH="$ROOT_DIR/DSkiller-1.0.0.dmg"

echo "=================================================="
echo "Starting DSkiller Packaging Process"
echo "=================================================="

# Check if the compiled DSkiller.app exists
if [ ! -d "$APP_PATH" ]; then
  echo "Error: Compiled application not found at: $APP_PATH"
  echo "Please run build_app.sh first!"
  exit 1
fi

# Clean up any existing DMG
if [ -f "$DMG_PATH" ]; then
  echo "Removing existing DMG at: $DMG_PATH"
  rm -f "$DMG_PATH"
fi

# Create a temporary staging directory
TMP_DIR="$(mktemp -d -t dskiller-dmg-staging)"
echo "Created temporary staging folder: $TMP_DIR"

# Set up clean exit traps
cleanup() {
  echo "Cleaning up temporary staging folder..."
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Copy the app to the staging folder
echo "Copying DSkiller.app to staging..."
cp -R "$APP_PATH" "$TMP_DIR/DSkiller.app"

# Create symbolic link to /Applications for standard drag-and-drop installer experience
echo "Creating /Applications shortcut link..."
ln -s /Applications "$TMP_DIR/Applications"

# Create the DMG using hdiutil
echo "Creating compressed DMG: $DMG_PATH"
hdiutil create \
  -volname "DSkiller" \
  -srcfolder "$TMP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG successfully created!"

# Fulfill "不留app" (satisfy the requirement not to keep loose .app in workspace)
echo "Fulfilling '不留app' constraint: Deleting loose $APP_PATH from project root..."
rm -rf "$APP_PATH"

echo "=================================================="
echo "Packaging Completed Successfully!"
echo "Only DSkiller-1.0.0.dmg remains in workspace root."
echo "=================================================="
