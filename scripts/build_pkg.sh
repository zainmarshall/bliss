#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
PKG_DIR="${ROOT_DIR}/pkg_build"
PAYLOAD="${PKG_DIR}/payload"
SCRIPTS="${PKG_DIR}/scripts"
OUTPUT="${ROOT_DIR}/Bliss.pkg"

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "  ${BOLD}${CYAN}Building Bliss.pkg${RESET}"
echo ""

# ── Verify prebuilt artifacts exist ──────────────────────────────
TAURI_APP="${ROOT_DIR}/src-tauri/target/release/bundle/macos/Bliss.app"
CLI_DIR="${ROOT_DIR}/build"

if [[ ! -d "${TAURI_APP}" ]]; then
  echo "  Tauri app not found. Building..."
  cd "${ROOT_DIR}" && npm run tauri build 2>&1 | tail -3
fi

if [[ ! -f "${CLI_DIR}/bliss" ]]; then
  echo "  CLI not found. Building..."
  cmake -S "${ROOT_DIR}" -B "${CLI_DIR}" >/dev/null 2>&1
  cmake --build "${CLI_DIR}"
fi

echo -e "  ${GREEN}✓${RESET} Artifacts ready"

# ── Clean and create payload structure ───────────────────────────
rm -rf "${PKG_DIR}"
mkdir -p "${PAYLOAD}/usr/local/bin"
mkdir -p "${PAYLOAD}/usr/local/share/bliss/quotes"
mkdir -p "${PAYLOAD}/usr/local/share/bliss/problems"
mkdir -p "${PAYLOAD}/Applications"
mkdir -p "${PAYLOAD}/Library/LaunchDaemons"
mkdir -p "${SCRIPTS}"

# ── Copy files into payload ──────────────────────────────────────
# CLI binaries
cp "${CLI_DIR}/bliss" "${CLI_DIR}/blissd" "${CLI_DIR}/blissroot" "${PAYLOAD}/usr/local/bin/"
chmod 755 "${PAYLOAD}/usr/local/bin/bliss" "${PAYLOAD}/usr/local/bin/blissd" "${PAYLOAD}/usr/local/bin/blissroot"

# Tauri app - build the bundle manually from the binary to avoid root ownership issues
TAURI_BIN="${ROOT_DIR}/src-tauri/target/release/app"
TAURI_ICON="${ROOT_DIR}/src-tauri/icons/icon.icns"
TAURI_PLIST="${TAURI_APP}/Contents/Info.plist"
APP_DEST="${PAYLOAD}/Applications/Bliss.app"
mkdir -p "${APP_DEST}/Contents/MacOS" "${APP_DEST}/Contents/Resources"
cp "${TAURI_BIN}" "${APP_DEST}/Contents/MacOS/app"
cp "${TAURI_ICON}" "${APP_DEST}/Contents/Resources/icon.icns"
# Copy tray icon into the bundle so it's available at runtime
cp "${ROOT_DIR}/src-tauri/icons/tray-icon@2x.png" "${APP_DEST}/Contents/Resources/" 2>/dev/null || true
cat > "${APP_DEST}/Contents/Info.plist" << 'BPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>app</string>
  <key>CFBundleIdentifier</key><string>com.bliss.installed</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Bliss</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
BPLIST
chmod 755 "${APP_DEST}/Contents/MacOS/app"

# Data files
cp "${ROOT_DIR}/quotes/"*.txt "${PAYLOAD}/usr/local/share/bliss/quotes/" 2>/dev/null || true
cp "${ROOT_DIR}/problems/"*.json "${PAYLOAD}/usr/local/share/bliss/problems/" 2>/dev/null || true
cp "${ROOT_DIR}/scripts/uninstall.sh" "${PAYLOAD}/usr/local/share/bliss/uninstall.sh"
chmod 755 "${PAYLOAD}/usr/local/share/bliss/uninstall.sh"

# Root helper plist
cp "${ROOT_DIR}/root/com.bliss.root.plist" "${PAYLOAD}/Library/LaunchDaemons/com.bliss.root.plist"
cp "${ROOT_DIR}/root/com.bliss.root.plist" "${PAYLOAD}/usr/local/share/bliss/com.bliss.root.plist"

echo -e "  ${GREEN}✓${RESET} Payload assembled"

# ── Postinstall script ───────────────────────────────────────────
cat > "${SCRIPTS}/postinstall" << 'POSTINSTALL'
#!/bin/bash

# Codesign binaries
/usr/bin/codesign --force --sign - /usr/local/bin/bliss >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - /usr/local/bin/blissd >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - /usr/local/bin/blissroot >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - /Applications/Bliss.app >/dev/null 2>&1 || true

# Kill old menubar if present
/usr/bin/killall blissbar 2>/dev/null || true

# Register root helper
/bin/launchctl bootout system/com.bliss.root 2>/dev/null || true
/bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist 2>/dev/null || true
/bin/launchctl kickstart -k system/com.bliss.root 2>/dev/null || true

# Open the app
/usr/bin/open /Applications/Bliss.app &

exit 0
POSTINSTALL
chmod 755 "${SCRIPTS}/postinstall"

echo -e "  ${GREEN}✓${RESET} Scripts created"

# ── Build the pkg directly with pkgbuild ─────────────────────────
# Use a pkg-specific identifier (different from the app's CFBundleIdentifier)
# to prevent macOS from "relocating" the app to the build directory
pkgbuild \
  --root "${PAYLOAD}" \
  --scripts "${SCRIPTS}" \
  --identifier "com.bliss.installer" \
  --version "1.0.0" \
  --install-location "/" \
  --ownership recommended \
  "${OUTPUT}" \
  >/dev/null 2>&1

echo -e "  ${GREEN}✓${RESET} Package built"

# ── Cleanup ──────────────────────────────────────────────────────
rm -rf "${PKG_DIR}"

echo ""
echo -e "  ${GREEN}${BOLD}Done!${RESET} ${DIM}${OUTPUT}${RESET}"
echo ""
echo -e "  ${DIM}Double-click Bliss.pkg to install, or:${RESET}"
echo -e "  ${DIM}sudo installer -pkg Bliss.pkg -target /${RESET}"
echo ""
