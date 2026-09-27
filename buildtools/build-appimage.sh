#!/usr/bin/env bash
set -euo pipefail

APP_DIR="SolWatt.AppDir"
APPIMAGE_TOOL="buildtools/appimagetool-x86_64.AppImage"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -r build/linux/x64/release/bundle/* "$APP_DIR"
cp -r buildtools/appimage_config/* "$APP_DIR"
cp assets/icons/icon-padded.png "$APP_DIR"
chmod +x "$APPIMAGE_TOOL"
chmod +x "$APP_DIR/AppRun"
"$APPIMAGE_TOOL" "$APP_DIR"
