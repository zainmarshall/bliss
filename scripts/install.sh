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

# ── Step 2: Build GUI (Tauri) ─────────────────────────────────────
step "Building GUI"

TAURI_APP="${ROOT_DIR}/src-tauri/target/release/bundle/macos/Bliss.app"

if [[ -d "${TAURI_APP}" && -f "${TAURI_APP}/Contents/MacOS/app" ]]; then
  ok "Using prebuilt Tauri app"
else
  info "Building Tauri app..."
  cd "${ROOT_DIR}"
  npm run tauri build 2>&1 | tail -3
  if [[ -d "${TAURI_APP}" ]]; then
    ok "Tauri GUI built"
  else
    fail "Tauri build failed"
    exit 1
  fi
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
  cp -R '${TAURI_APP}' /Applications/Bliss.app
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

# Kill old SwiftUI menubar binary if present
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
printf "  ${DIM}Bliss lives in your menu bar. Close the window to keep it running.${RESET}\n"
printf "\n"
