#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[bliss] install: starting"

INSTALL_BIN="/usr/local/bin"
echo "[bliss] install: binaries"
sudo mkdir -p "${INSTALL_BIN}"

if [[ -f "${ROOT_DIR}/bliss" && -f "${ROOT_DIR}/blissd" && -f "${ROOT_DIR}/blissroot" ]]; then
  sudo cp "${ROOT_DIR}/bliss" "${INSTALL_BIN}/bliss"
  sudo cp "${ROOT_DIR}/blissd" "${INSTALL_BIN}/blissd"
  sudo cp "${ROOT_DIR}/blissroot" "${INSTALL_BIN}/blissroot"
else
  cmake -S "${ROOT_DIR}" -B "${ROOT_DIR}/build"
  cmake --build "${ROOT_DIR}/build"
  sudo cp "${ROOT_DIR}/build/bliss" "${INSTALL_BIN}/bliss"
  sudo cp "${ROOT_DIR}/build/blissd" "${INSTALL_BIN}/blissd"
  sudo cp "${ROOT_DIR}/build/blissroot" "${INSTALL_BIN}/blissroot"
fi
sudo chmod 755 "${INSTALL_BIN}/bliss" "${INSTALL_BIN}/blissd" "${INSTALL_BIN}/blissroot"
sudo /usr/bin/codesign --force --sign - "${INSTALL_BIN}/bliss" "${INSTALL_BIN}/blissd" "${INSTALL_BIN}/blissroot" >/dev/null 2>&1 || true

echo "[bliss] install: shared files"
sudo mkdir -p /usr/local/share/bliss
sudo cp "${ROOT_DIR}/quotes.txt" /usr/local/share/bliss/quotes.txt
sudo cp "${ROOT_DIR}/scripts/uninstall.sh" /usr/local/share/bliss/uninstall.sh
sudo chmod 755 /usr/local/share/bliss/uninstall.sh

echo "[bliss] install: menubar"
bash "${ROOT_DIR}/scripts/install_menubar.sh"

echo "[bliss] install: root helper"
sudo cp "${ROOT_DIR}/root/com.bliss.root.plist" /Library/LaunchDaemons/com.bliss.root.plist
sudo /bin/launchctl bootout system/com.bliss.root 2>/dev/null || true
retry=0
while true; do
  if sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist 2>/dev/null; then
    break
  fi
  retry=$((retry+1))
  if [[ "${retry}" -ge 3 ]]; then
    echo "blissroot launchd bootstrap failed; try: sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist"
    break
  fi
  sleep 1
done
sudo /bin/launchctl kickstart -k system/com.bliss.root 2>/dev/null || true

echo "[bliss] install: done"
