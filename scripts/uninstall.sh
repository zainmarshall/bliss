#!/usr/bin/env bash
set -euo pipefail

# Resolve the real user — SUDO_USER is set under sudo but NOT under osascript.
# Fall back to the console owner (the logged-in GUI user).
if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_USER="${SUDO_USER}"
elif [[ "$(id -u)" -eq 0 ]]; then
  REAL_USER="$(/usr/bin/stat -f '%Su' /dev/console)"
else
  REAL_USER="$(whoami)"
fi
USER_HOME="$(/usr/bin/dscl . -read /Users/${REAL_USER} NFSHomeDirectory | /usr/bin/awk '{print $2}')"
USER_UID="$(id -u "${REAL_USER}")"

/bin/launchctl bootout system/com.bliss.timer 2>/dev/null || true
/bin/launchctl bootout "gui/${USER_UID}/com.bliss.menubar" 2>/dev/null || true
/bin/launchctl bootout system/com.bliss.root 2>/dev/null || true

# Kill running processes
/usr/bin/killall Bliss 2>/dev/null || true
/usr/bin/killall blissbar 2>/dev/null || true

rm -f /usr/local/bin/bliss /usr/local/bin/blissd
rm -f /usr/local/bin/blissroot
rm -f /Library/LaunchDaemons/com.bliss.timer.plist
rm -f /Library/LaunchDaemons/com.bliss.root.plist

rm -f "${USER_HOME}/Library/LaunchAgents/com.bliss.menubar.plist"
rm -rf "${USER_HOME}/Library/Application Support/Bliss"
rm -rf /Applications/Bliss.app
rm -rf /usr/local/share/bliss

rm -rf "${USER_HOME}/.config/bliss"
rm -f /var/db/bliss_end_time

rm -f /etc/pf.anchors/bliss
/sbin/pfctl -t bliss_block -T flush >/dev/null 2>&1 || true
/sbin/pfctl -t bliss_block -T kill >/dev/null 2>&1 || true
/sbin/pfctl -d >/dev/null 2>&1 || true
/sbin/pfctl -d >/dev/null 2>&1 || true

if /usr/bin/grep -q 'anchor "bliss"' /etc/pf.conf; then
  /usr/bin/sed -e '/anchor "bliss"/d' -e '/load anchor "bliss" from "\/etc\/pf\.anchors\/bliss"/d' /etc/pf.conf > /tmp/bliss_pf_clean.conf
  mv /tmp/bliss_pf_clean.conf /etc/pf.conf
  /sbin/pfctl -f /etc/pf.conf 2>/dev/null || true
fi

if /usr/bin/grep -q "# bliss-block start" /etc/hosts; then
  /usr/bin/awk '
    $0 ~ /# bliss-block start/ {skip=1}
    skip && $0 ~ /# bliss-block end/ {skip=0; next}
    !skip {print}
  ' /etc/hosts > /tmp/bliss_hosts_clean
  mv /tmp/bliss_hosts_clean /etc/hosts
  /usr/bin/dscacheutil -flushcache
  /usr/bin/killall -HUP mDNSResponder
fi

echo "bliss removed"
