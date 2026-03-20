# Bliss
Bliss is a macOS focus lock that blocks distracting websites, force-closes apps, and makes you solve a real challenge to escape early. It has a native SwiftUI GUI, a menubar countdown, and a CLI.

# MACOS Only. To all Windows and Linux users of Flavortown, please watch the following video demo to get a full understanding of the app!

## Video Demo
https://github.com/user-attachments/assets/c681f4bc-3413-435e-bcb4-4d17c81feb56



## What it does

- Blocks websites via /etc/hosts + pf firewall (dual-layer, browser-agnostic)
- Force-closes blocked apps during a session
- Background timer (`blissd`) survives terminal close and reboot
- Menubar countdown (always visible)
- Two panic modes: typing challenge (95% accuracy) or competitive programming (solve a real CSES problem)
- Native SwiftUI GUI with setup wizard, config menu, timer and keyboard shortcuts
- CLI for power users

## Install

```bash
curl -fsSL \
  "https://github.com/zainmarshall/bliss/releases/download/v0.4.0/bliss-macos-universal.zip" \
  -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```

That’s it. No Xcode, no build tools. The installer sets up everything: CLI, GUI, menubar app, and root helper. A setup wizard walks you through configuration on first launch.

If you see `Bootstrap failed: 5: Input/output error`, just re-run the command.

## CLI Commands

| Command | Description |
|---------|-------------|
| `bliss start <minutes>` | Start a focus session |
| `bliss panic` | Escape early (typing challenge or opens GUI for competitive) |
| `bliss status` | Show timer and firewall state |
| `bliss config website add/remove/list` | Manage blocked websites |
| `bliss config app add/remove/list` | Manage blocked apps |
| `bliss config browser add/remove/list` | Manage browsers to restart |
| `bliss config quotes short/medium/long/huge` | Set typing challenge length |
| `bliss repair` | Fix root helper (requires sudo) |
| `bliss uninstall` | Remove everything (requires sudo + challenge) |

## Notes
- Starting a session restarts configured browsers to flush DNS caches. Save your work first.
- Nothing is blocked by default -- configure via the GUI wizard or CLI.

## Architecture
- **Blocking:** `/etc/hosts` + pf firewall table for redundant, browser-agnostic blocking
- **Timer:** `blissd` LaunchAgent daemon, epoch-based, survives reboots
- **Root helper:** `blissroot` LaunchDaemon so no sudo needed after install
- **GUI:** Native SwiftUI app with setup wizard, two panic modes, real app icons
- **Menubar:** Lightweight Cocoa status bar app showing countdown
- **Config:** `~/.config/bliss/` (plain text files)

## Devlogs
Read the devlogs at: https://flavortown.hackclub.com/projects/11291
