#!/usr/bin/env bash
set -euo pipefail

sudo /bin/launchctl bootout system/com.bliss.timer 2>/dev/null || true
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_UID="$(id -u "${SUDO_USER}")"
  /bin/launchctl bootout "gui/${USER_UID}/com.bliss.menubar" 2>/dev/null || true
fi
sudo /bin/launchctl bootout system/com.bliss.root 2>/dev/null || true

sudo rm -f /usr/local/bin/bliss /usr/local/bin/blissd
sudo rm -f /usr/local/bin/blissroot
sudo rm -f /Library/LaunchDaemons/com.bliss.timer.plist
sudo rm -f /Library/LaunchDaemons/com.bliss.root.plist

USER_HOME="${HOME}"
if [[ -n "${SUDO_USER:-}" ]]; then
  USER_HOME="$(/usr/bin/dscl . -read /Users/${SUDO_USER} NFSHomeDirectory | /usr/bin/awk '{print $2}')"
fi

rm -f "${USER_HOME}/Library/LaunchAgents/com.bliss.menubar.plist"
rm -rf "${USER_HOME}/Library/Application Support/Bliss"
sudo rm -rf /usr/local/share/bliss

rm -rf "${USER_HOME}/.config/bliss"
sudo rm -f /var/db/bliss_end_time

sudo rm -f /etc/pf.anchors/bliss
sudo /sbin/pfctl -t bliss_block -T flush >/dev/null 2>&1 || true

if /usr/bin/grep -q 'anchor "bliss"' /etc/pf.conf; then
  sudo /usr/bin/sed -e '/anchor "bliss"/d' -e '/load anchor "bliss" from "\/etc\/pf\.anchors\/bliss"/d' /etc/pf.conf | sudo /usr/bin/tee /etc/pf.conf >/dev/null
  sudo /sbin/pfctl -f /etc/pf.conf
fi

if /usr/bin/grep -q "# bliss-block start" /etc/hosts; then
  sudo /usr/bin/awk '
    $0 ~ /# bliss-block start/ {skip=1}
    skip && $0 ~ /# bliss-block end/ {skip=0; next}
    !skip {print}
  ' /etc/hosts | sudo /usr/bin/tee /etc/hosts >/dev/null
  sudo /usr/bin/dscacheutil -flushcache
  sudo /usr/bin/killall -HUP mDNSResponder
fi

echo "bliss removed"
