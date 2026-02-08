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

if [[ -f "${PREBUILT_BIN}" ]]; then
  echo "[bliss] menubar: using prebuilt binary"
  mkdir -p "${BUILD_DIR}"
  cp "${PREBUILT_BIN}" "${BIN}"
else
  echo "[bliss] menubar: building from source"
  mkdir -p "${BUILD_DIR}"
  /usr/bin/swiftc -framework Cocoa "${SRC}" -o "${BIN}"
fi

INSTALL_DIR="${HOME}/Library/Application Support/Bliss"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.bliss.menubar.plist"
echo "[bliss] menubar: installing"
mkdir -p "${INSTALL_DIR}"
cp "${BIN}" "${INSTALL_DIR}/blissbar"

sed "s|__BLISSBAR_PATH__|${INSTALL_DIR}/blissbar|g" "${PLIST_SRC}" > "${LAUNCH_AGENT}"

chmod 644 "${LAUNCH_AGENT}"
chmod 755 "${INSTALL_DIR}/blissbar"

/bin/launchctl bootout "gui/$(id -u)/com.bliss.menubar" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT}"
/bin/launchctl kickstart -k "gui/$(id -u)/com.bliss.menubar"

echo "[bliss] menubar: installed and running"
