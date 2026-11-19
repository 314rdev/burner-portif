#!/usr/bin/env bash
# Installs the Burner release build for the current user so it shows up in
# the Ubuntu app grid / dock with its icon.
#
#   flutter build linux --release --dart-define-from-file=config/firebase.env.json
#   ./linux/install-desktop-entry.sh
#
# Re-run after each new build. Remove with: ./linux/install-desktop-entry.sh --uninstall
set -euo pipefail

APP_ID="com.example.burner"          # must match APPLICATION_ID in linux/CMakeLists.txt
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA/burner"
DESKTOP_FILE="$DATA/applications/$APP_ID.desktop"
ICON_FILE="$DATA/icons/hicolor/512x512/apps/$APP_ID.png"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$INSTALL_DIR" "$DESKTOP_FILE" "$ICON_FILE"
  update-desktop-database "$DATA/applications" 2>/dev/null || true
  echo "Burner removed."
  exit 0
fi

if [[ ! -x "$BUNDLE/burner" ]]; then
  echo "No release build at $BUNDLE. Run:" >&2
  echo "  flutter build linux --release --dart-define-from-file=config/firebase.env.json" >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$(dirname "$DESKTOP_FILE")" "$(dirname "$ICON_FILE")"
cp -r "$BUNDLE/." "$INSTALL_DIR/"
cp "$ROOT/linux/icons/burner.png" "$ICON_FILE"

cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Burner
Comment=Send files and text between your devices
Exec=$INSTALL_DIR/burner
Icon=$APP_ID
Terminal=false
Categories=Network;FileTransfer;Utility;
StartupNotify=true
StartupWMClass=burner
DESKTOP

update-desktop-database "$DATA/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$DATA/icons/hicolor" 2>/dev/null || true
echo "Burner installed to $INSTALL_DIR. Find it in your app grid."
