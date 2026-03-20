#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_BIN="/usr/local/bin"
SHARE_DIR="/usr/local/share/bliss"

# ── Colors & helpers ─────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

step_num=0
total_steps=5

step() {
  step_num=$((step_num + 1))
  printf "\n${BOLD}${CYAN}[%d/%d]${RESET} ${BOLD}%s${RESET}\n" "$step_num" "$total_steps" "$1"
}

info() {
  printf "  ${DIM}%s${RESET}\n" "$1"
}

ok() {
  printf "  ${GREEN}✓${RESET} %s\n" "$1"
}

warn() {
  printf "  ${YELLOW}!${RESET} %s\n" "$1"
}

fail() {
  printf "  ${RED}✗${RESET} %s\n" "$1"
}

progress_bar() {
  local current=$1 total=$2 width=30
  local filled=$((current * width / total))
  local empty=$((width - filled))
  printf "\r  ${DIM}[${GREEN}%s${DIM}%s${DIM}]${RESET} " \
    "$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null || true)" \
    "$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null || true)"
}

# ── Header ───────────────────────────────────────────────────────
printf "\n"
printf "  ${BOLD}${CYAN}┌──────────────────────────────┐${RESET}\n"
printf "  ${BOLD}${CYAN}│       Bliss Installer        │${RESET}\n"
printf "  ${BOLD}${CYAN}└──────────────────────────────┘${RESET}\n"

# ── Step 1: Build CLI ────────────────────────────────────────────
step "Building CLI"

if [[ -f "${ROOT_DIR}/build/bliss" && -f "${ROOT_DIR}/build/blissd" && -f "${ROOT_DIR}/build/blissroot" ]]; then
  ok "Using prebuilt CLI binaries"
else
  info "Compiling from source..."
  cmake -S "${ROOT_DIR}" -B "${ROOT_DIR}/build" >/dev/null 2>&1
  cmake --build "${ROOT_DIR}/build"
  ok "CLI built"
fi

# ── Step 2: Build GUI ───────────────────────────────────────────
step "Building GUI"

PREBUILT_APP="${ROOT_DIR}/gui/build/Bliss.app"
GUI_BUILD_DIR="${ROOT_DIR}/gui/build_install"
GUI_APP_BUNDLE="${GUI_BUILD_DIR}/Bliss.app"
GUI_APP_CONTENTS="${GUI_APP_BUNDLE}/Contents"
GUI_APP_MACOS="${GUI_APP_CONTENTS}/MacOS"
GUI_APP_RESOURCES="${GUI_APP_CONTENTS}/Resources"
GUI_APP_BIN="${GUI_APP_MACOS}/Bliss"

if [[ -f "${PREBUILT_APP}/Contents/MacOS/Bliss" ]]; then
  rm -rf "${GUI_APP_BUNDLE}"
  mkdir -p "${GUI_BUILD_DIR}"
  cp -R "${PREBUILT_APP}" "${GUI_APP_BUNDLE}"
  ok "Using prebuilt GUI"
else
  info "Compiling SwiftUI app..."
  mkdir -p "${GUI_APP_MACOS}" "${GUI_APP_RESOURCES}/problems" "${GUI_APP_RESOURCES}/quotes"
  cp -f "${ROOT_DIR}/problems/"*.json "${GUI_APP_RESOURCES}/problems/" 2>/dev/null || true
  cp -f "${ROOT_DIR}/quotes/"*.txt "${GUI_APP_RESOURCES}/quotes/" 2>/dev/null || true
  cp -f "${ROOT_DIR}/gui/AppIcon.icns" "${GUI_APP_RESOURCES}/AppIcon.icns" 2>/dev/null || true
  /usr/bin/swiftc -parse-as-library -module-cache-path /tmp/bliss_module_cache \
    -framework SwiftUI -framework AppKit -framework UserNotifications \
    "${ROOT_DIR}/gui/"*.swift -o "${GUI_APP_BIN}"
  cat > "${GUI_APP_CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Bliss</string>
  <key>CFBundleIdentifier</key><string>com.bliss.gui</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Bliss</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.4.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.bliss.gui</string>
    <key>CFBundleURLSchemes</key><array><string>bliss</string></array>
  </dict></array>
</dict>
</plist>
PLIST
  ok "GUI built"
fi

# ── Step 3: Install files ───────────────────────────────────────
step "Installing files"

info "This requires sudo access..."
sudo bash -c "
  mkdir -p '${INSTALL_BIN}' '${SHARE_DIR}/quotes' '${SHARE_DIR}/problems'

  cp '${ROOT_DIR}/build/bliss' '${ROOT_DIR}/build/blissd' '${ROOT_DIR}/build/blissroot' '${INSTALL_BIN}/'
  chmod 755 '${INSTALL_BIN}/bliss' '${INSTALL_BIN}/blissd' '${INSTALL_BIN}/blissroot'
  /usr/bin/codesign --force --sign - '${INSTALL_BIN}/bliss' '${INSTALL_BIN}/blissd' '${INSTALL_BIN}/blissroot' >/dev/null 2>&1 || true

  cp '${ROOT_DIR}/quotes/'*.txt '${SHARE_DIR}/quotes/' 2>/dev/null || true
  cp '${ROOT_DIR}/problems/'*.json '${SHARE_DIR}/problems/' 2>/dev/null || true
  cp '${ROOT_DIR}/scripts/uninstall.sh' '${SHARE_DIR}/uninstall.sh'
  chmod 755 '${SHARE_DIR}/uninstall.sh'

  rm -rf /Applications/Bliss.app
  cp -R '${GUI_APP_BUNDLE}' /Applications/Bliss.app
  /usr/bin/codesign --force --sign - /Applications/Bliss.app >/dev/null 2>&1 || true
"
ok "CLI binaries  -> ${INSTALL_BIN}/"
ok "Bliss.app     -> /Applications/"
ok "Quotes & data -> ${SHARE_DIR}/"

# ── Step 4: Root helper ─────────────────────────────────────────
step "Setting up root helper"

ROOT_PLIST=""
if [[ -f "${ROOT_DIR}/root/com.bliss.root.plist" ]]; then
  ROOT_PLIST="${ROOT_DIR}/root/com.bliss.root.plist"
elif [[ -f "${ROOT_DIR}/root.plist" ]]; then
  ROOT_PLIST="${ROOT_DIR}/root.plist"
fi
if [[ -z "${ROOT_PLIST}" ]]; then
  warn "Missing com.bliss.root.plist - root helper not installed"
else
  sudo cp "${ROOT_PLIST}" /Library/LaunchDaemons/com.bliss.root.plist
  sudo cp "${ROOT_PLIST}" "${SHARE_DIR}/com.bliss.root.plist"
  sudo /bin/launchctl bootout system/com.bliss.root 2>/dev/null || true
  if ! sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist 2>/dev/null; then
    warn "launchd bootstrap failed; try: sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist"
  else
    ok "Root helper registered"
  fi
  sudo /bin/launchctl kickstart -k system/com.bliss.root 2>/dev/null || true
fi

# ── Step 5: Cleanup ─────────────────────────────────────────────
step "Finishing up"

# Kill old standalone menubar binary if present (now built into Bliss.app)
if [[ -n "${SUDO_UID:-}" ]]; then
  /bin/launchctl bootout "gui/${SUDO_UID}/com.bliss.menubar" 2>/dev/null || true
else
  /bin/launchctl bootout "gui/$(id -u)/com.bliss.menubar" 2>/dev/null || true
fi
/usr/bin/killall blissbar 2>/dev/null || true
ok "Done"

# ── Done ─────────────────────────────────────────────────────────
printf "\n"
printf "  ${GREEN}${BOLD}Installation complete!${RESET}\n"
printf "\n"
printf "  ${BOLD}Quick start:${RESET}\n"
printf "    ${CYAN}1.${RESET} Open ${BOLD}Bliss.app${RESET} from /Applications\n"
printf "    ${CYAN}2.${RESET} Add websites and apps to block\n"
printf "    ${CYAN}3.${RESET} Start a focus session\n"
printf "\n"
printf "  ${BOLD}CLI usage:${RESET}\n"
printf "    ${DIM}bliss config website add youtube.com${RESET}\n"
printf "    ${DIM}bliss config app add${RESET}\n"
printf "    ${DIM}bliss start 45${RESET}\n"
printf "\n"
printf "  ${DIM}Note: Browsers in your config will be closed when a session starts.${RESET}\n"
printf "\n"
