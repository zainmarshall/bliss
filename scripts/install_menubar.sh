#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[bliss] menubar: preparing..."
PREBUILT_BIN="${ROOT_DIR}/menubar/blissbar"
BUILD_DIR="${ROOT_DIR}/menubar/build"
BIN="${BUILD_DIR}/blissbar"
SRC="${ROOT_DIR}/menubar/main.swift"
PLIST_SRC="${ROOT_DIR}/menubar/com.bliss.menubar.plist"

if [[ ! -f "${PREBUILT_BIN}" && ! -f "${SRC}" ]]; then
  echo "[bliss] menubar: not found in release package; skipping"
  exit 0
fi

if [[ ! -f "${PLIST_SRC}" ]]; then
  echo "[bliss] menubar: plist missing; skipping"
  exit 0
fi

if [[ -f "${SRC}" ]]; then
  echo "[bliss] menubar: building from source"
  mkdir -p "${BUILD_DIR}"
  # Kill running blissbar and remove old binary so linker can write
  /usr/bin/killall blissbar 2>/dev/null || true
  rm -f "${BIN}" 2>/dev/null || sudo rm -f "${BIN}" 2>/dev/null || true
  /usr/bin/swiftc -framework Cocoa "${SRC}" -o "${BIN}"
elif [[ -f "${PREBUILT_BIN}" ]]; then
  echo "[bliss] menubar: using prebuilt binary"
  mkdir -p "${BUILD_DIR}"
  cp "${PREBUILT_BIN}" "${BIN}"
fi

# Resolve the real user's home directory (not root's when running under sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
  _REAL_HOME=$( dscl . -read /Users/"${SUDO_USER}" NFSHomeDirectory | awk '{print $2}' )
else
  _REAL_HOME="${HOME}"
fi

INSTALL_DIR="${_REAL_HOME}/Library/Application Support/Bliss"
LAUNCH_AGENT="${_REAL_HOME}/Library/LaunchAgents/com.bliss.menubar.plist"
echo "[bliss] menubar: installing"
mkdir -p "${INSTALL_DIR}"
cp "${BIN}" "${INSTALL_DIR}/blissbar"

sed "s|__BLISSBAR_PATH__|${INSTALL_DIR}/blissbar|g" "${PLIST_SRC}" > "${LAUNCH_AGENT}"

chmod 644 "${LAUNCH_AGENT}"
chmod 755 "${INSTALL_DIR}/blissbar"

# Fix ownership if running under sudo
if [[ -n "${SUDO_USER:-}" ]]; then
  chown -R "${SUDO_USER}" "${INSTALL_DIR}" "${LAUNCH_AGENT}" 2>/dev/null || true
  # Fix source tree build dir so non-sudo make still works
  chown -R "${SUDO_USER}" "${BUILD_DIR}" 2>/dev/null || true
fi

# Resolve the real (non-root) user UID for launchctl gui domain
if [[ -n "${SUDO_UID:-}" ]]; then
  _BLISS_UID="${SUDO_UID}"
else
  _BLISS_UID="$(id -u)"
fi

/bin/launchctl bootout "gui/${_BLISS_UID}/com.bliss.menubar" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/${_BLISS_UID}" "${LAUNCH_AGENT}" 2>/dev/null || true
/bin/launchctl kickstart -k "gui/${_BLISS_UID}/com.bliss.menubar" 2>/dev/null || true
echo "[bliss] menubar: installed"
