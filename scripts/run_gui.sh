#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI_DIR="${ROOT_DIR}/gui"
BUILD_DIR="${GUI_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/BlissGUI.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_RESOURCES="${APP_CONTENTS}/Resources"
APP_BIN="${APP_MACOS}/BlissGUI"
INFO_PLIST="${APP_CONTENTS}/Info.plist"

mkdir -p "${APP_MACOS}" "${APP_RESOURCES}"

if [[ ! -f "${APP_BIN}" ]] || /usr/bin/find "${GUI_DIR}" -maxdepth 1 -name "*.swift" -newer "${APP_BIN}" | /usr/bin/grep -q .; then
  echo "[bliss-gui] compiling..."
  /usr/bin/swiftc -parse-as-library -module-cache-path /tmp/bliss_module_cache -framework SwiftUI -framework AppKit "${GUI_DIR}"/*.swift -o "${APP_BIN}"
fi

cat > "${INFO_PLIST}" <<'PLIST'
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

echo "[bliss-gui] launching..."
/usr/bin/open "${APP_BUNDLE}"
