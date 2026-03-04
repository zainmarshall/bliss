#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[bliss] install: starting"

INSTALL_BIN="/usr/local/bin"
GUI_BUILD_DIR="${ROOT_DIR}/gui/build_install"
GUI_APP_BUNDLE="${GUI_BUILD_DIR}/BlissGUI.app"
GUI_APP_CONTENTS="${GUI_APP_BUNDLE}/Contents"
GUI_APP_MACOS="${GUI_APP_CONTENTS}/MacOS"
GUI_APP_RESOURCES="${GUI_APP_CONTENTS}/Resources"
GUI_APP_BIN="${GUI_APP_MACOS}/BlissGUI"
GUI_INFO_PLIST="${GUI_APP_CONTENTS}/Info.plist"
echo "[bliss] install: binaries"
sudo mkdir -p "${INSTALL_BIN}"

cmake -S "${ROOT_DIR}" -B "${ROOT_DIR}/build"
cmake --build "${ROOT_DIR}/build"
sudo cp "${ROOT_DIR}/build/bliss" "${INSTALL_BIN}/bliss"
sudo cp "${ROOT_DIR}/build/blissd" "${INSTALL_BIN}/blissd"
sudo cp "${ROOT_DIR}/build/blissroot" "${INSTALL_BIN}/blissroot"
sudo chmod 755 "${INSTALL_BIN}/bliss" "${INSTALL_BIN}/blissd" "${INSTALL_BIN}/blissroot"
sudo /usr/bin/codesign --force --sign - "${INSTALL_BIN}/bliss" "${INSTALL_BIN}/blissd" "${INSTALL_BIN}/blissroot" >/dev/null 2>&1 || true

echo "[bliss] install: shared files"
sudo mkdir -p /usr/local/share/bliss
if [[ -d "${ROOT_DIR}/quotes" ]]; then
  sudo mkdir -p /usr/local/share/bliss/quotes
  sudo cp "${ROOT_DIR}/quotes/"*.txt /usr/local/share/bliss/quotes/
else
  sudo cp "${ROOT_DIR}/quotes.txt" /usr/local/share/bliss/quotes.txt
fi
sudo cp "${ROOT_DIR}/scripts/uninstall.sh" /usr/local/share/bliss/uninstall.sh
sudo chmod 755 /usr/local/share/bliss/uninstall.sh

echo "[bliss] install: gui"
mkdir -p "${GUI_APP_MACOS}" "${GUI_APP_RESOURCES}/problems"
/usr/bin/swiftc -parse-as-library -module-cache-path /tmp/bliss_module_cache -framework SwiftUI -framework AppKit "${ROOT_DIR}/gui/"*.swift -o "${GUI_APP_BIN}"
cp "${ROOT_DIR}/gui/problems/codeforces.json" "${GUI_APP_RESOURCES}/problems/codeforces.json"
cat > "${GUI_INFO_PLIST}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>BlissGUI</string>
  <key>CFBundleIdentifier</key>
  <string>com.bliss.gui</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>BlissGUI</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
sudo rm -rf /Applications/BlissGUI.app
sudo cp -R "${GUI_APP_BUNDLE}" /Applications/BlissGUI.app
sudo /usr/bin/codesign --force --sign - /Applications/BlissGUI.app >/dev/null 2>&1 || true

echo "[bliss] install: menubar"
bash "${ROOT_DIR}/scripts/install_menubar.sh"

echo "[bliss] install: root helper"
ROOT_PLIST=""
if [[ -f "${ROOT_DIR}/root/com.bliss.root.plist" ]]; then
  ROOT_PLIST="${ROOT_DIR}/root/com.bliss.root.plist"
elif [[ -f "${ROOT_DIR}/root.plist" ]]; then
  ROOT_PLIST="${ROOT_DIR}/root.plist"
fi
if [[ -z "${ROOT_PLIST}" ]]; then
  echo "[bliss] install: missing com.bliss.root.plist"
else
  sudo cp "${ROOT_PLIST}" /Library/LaunchDaemons/com.bliss.root.plist
  sudo cp "${ROOT_PLIST}" /usr/local/share/bliss/com.bliss.root.plist
fi
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

echo ""
echo "Quickstart"
echo "  1) Configure block list: bliss config website add example.com"
echo "  2) Add apps to block:    bliss config app add"
echo "  3) Add browsers to close: bliss config browser add"
echo "  4) Start a session:      bliss start 45"
echo ""
echo "Notes"
echo "  - Bliss ships with nothing configured by default."
echo "  - Browsers listed in config will be closed on start; save work first."
