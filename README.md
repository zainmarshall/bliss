# Bliss
Bliss is a focus lock that blocks distracting websites, force-closes apps, and makes you solve a real challenge to escape early. Cross-platform GUI (Tauri + Svelte) with a CLI for power users.

## Video Demo
https://github.com/user-attachments/assets/c681f4bc-3413-435e-bcb4-4d17c81feb56

## What it does

- **Block websites** via /etc/hosts + firewall (dual-layer, browser-agnostic)
- **Force-close apps** during a session
- **Survive everything** - background timer (`blissd`) persists through terminal close and reboot
- **Panic challenges** to escape early: Typing (100% accuracy), Competitive Programming, Minesweeper, Pipes, Sudoku, Simon Says, Wordle, 2048
- **Configs** - save/load blocking profiles, switch between them instantly
- **HH:MM:SS timer** - microwave-style digit entry, supports hours and seconds
- **Cross-platform** - macOS now, Linux coming (iptables backend already done)

## Install

```bash
curl -fsSL \
  "https://github.com/zainmarshall/bliss/releases/download/v0.4.0/bliss-macos-universal.zip" \
  -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```

No Xcode, no build tools. The installer sets up everything: CLI, GUI, and root helper.

If you see `Bootstrap failed: 5: Input/output error`, just re-run the command.

## Build from source

Requires: Rust, Cargo, Node.js, npm.

```bash
# Install dependencies
npm install

# Build the C++ backend
mkdir -p build && cd build && cmake .. && make && cd ..
sudo make install   # installs bliss, blissd, blissroot to /usr/local/bin

# Run the Tauri GUI in dev mode
cargo tauri dev
```

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
- Nothing is blocked by default - configure via the GUI or CLI.

## Architecture
- **Blocking:** `/etc/hosts` + firewall (pf on macOS, iptables on Linux) for redundant, browser-agnostic blocking
- **Timer:** `blissd` daemon, epoch-based, survives reboots
- **Root helper:** `blissroot` daemon so no sudo needed after install
- **GUI:** Tauri v2 + Svelte 5 (was SwiftUI, migrated for cross-platform)
- **Config:** `~/.config/bliss/` (plain text + JSON files)
- **Profiles:** `~/.config/bliss/profiles/*.json`

## Devlogs
Read the devlogs at: https://flavortown.hackclub.com/projects/11291
