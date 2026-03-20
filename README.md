# Bliss
Bliss is a macOS focus lock that blocks distracting websites, force-closes apps, and makes you solve a real challenge to escape early. Native SwiftUI GUI with scheduling, a menubar countdown, and a CLI for power users.

# MACOS Only. To all Windows and Linux users of Flavortown, please watch the following video demo to get a full understanding of the app!

## Video Demo
https://github.com/user-attachments/assets/c681f4bc-3413-435e-bcb4-4d17c81feb56



## What it does

- **Block websites** via /etc/hosts + pf firewall (dual-layer, browser-agnostic)
- **Force-close apps** during a session
- **Schedule sessions** on a weekly calendar tied to saved configs
- **Survive everything** — background timer (`blissd`) persists through terminal close and reboot
- **Menubar countdown** always visible
- **7 panic challenges** to escape early: Typing (100% accuracy), Competitive Programming, Minesweeper, Pipes, Sudoku, Simon Says, Wordle, 2048
- **Configs** — save/load blocking profiles with custom colors, switch between them instantly
- **HH:MM:SS timer** — microwave-style digit entry, supports hours and seconds
- **Setup wizard** walks you through everything on first launch

## Install

```bash
curl -fsSL \
  "https://github.com/zainmarshall/bliss/releases/download/v0.3.0/bliss-macos-universal.zip" \
  -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```

That's it. No Xcode, no build tools. The installer sets up everything: CLI, GUI, menubar app, and root helper. A setup wizard walks you through configuration on first launch.

If you see `Bootstrap failed: 5: Input/output error`, just re-run the command.

## The GUI

**Session tab** — Big HH:MM:SS timer display. Click and type digits (they fill from the right like a microwave). Hit Enter or click Start.

**Schedule tab** — Weekly calendar grid showing all your scheduled sessions color-coded by config. Add schedules with day toggles, 12h time picker with AM/PM, and duration. Sessions auto-start at the scheduled time.

**Statistics tab** — Session count, focus hours, streak tracking, and a GitHub-style activity heatmap.

**Settings tab** — Configs (save/load with color picker), panic challenge selection with segmented difficulty pickers, blocked websites with preset packs, blocked apps, browser management, troubleshooting, and uninstall.

**Menubar** — Always-visible countdown. Quick access to open the app, start a session, trigger panic, or open settings.

## CLI Commands

| Command | Description |
|---------|-------------|
| `bliss start <minutes>` | Start a focus session |
| `bliss start <seconds> --seconds` | Start with exact seconds |
| `bliss panic` | Escape early (must complete a challenge) |
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
- Closing the window hides the app to menubar. It's still running. Use "Quit Bliss" from the menubar to fully exit.

## Architecture
- **Blocking:** `/etc/hosts` + pf firewall table for redundant, browser-agnostic blocking
- **Timer:** `blissd` LaunchAgent daemon, epoch-based, survives reboots
- **Root helper:** `blissroot` LaunchDaemon so no sudo needed after install
- **GUI:** Native SwiftUI app with setup wizard, scheduling, 8 panic modes
- **Menubar:** Integrated into the app, shows countdown
- **Config:** `~/.config/bliss/` (plain text + JSON files)
- **Scheduling:** `~/.config/bliss/schedules.json`, checked every 5 seconds

## Devlogs
Read the devlogs at: https://flavortown.hackclub.com/projects/11291
