# Bliss
Bliss is a macOS focus lock that blocks distracting websites and force‑closes selected apps. It runs a background timer, shows a menubar countdown, and makes you solve a typing challenge to escape early.

## What it does

- Blocks websites via /etc/hosts + pf firewall table
- Force‑closes blocked apps during a session
- Runs a background timer (blissd) so the lock survives terminal close or reboot
- Menubar timer (always‑on status)
- Panic mode typing challenge

## Quick start

- Install using this command 
 ```bash
curl -fsSL https://github.com/zainmarshall/bliss/releases/download/v0.1.0/bliss-macos-universal.zip -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```
- bliss config website add <domain>
- bliss config app add (This will open a menu for you to select apps)
- bliss start 25

Commands

- bliss start <minutes> - Starts a timer for <minutes> minutes
- bliss panic - Escape a block early by completing a typing challenge.
- bliss status - Status of the timer and pf table
- bliss uninstall - Uninstalls everything. Must run with sudo. Requires a typing challenge. 
- bliss config website add/remove <domain> - Add or remove websites from block
- bliss config website list - list blocked websites
- bliss config app add/remove - Opens a menu to select apps to add / remove from the block
- bliss config app list - list blocked apps
- bliss config quotes short/medium/long/huge - Configure the length of quotes used in the typing challenges. 

## Architecture & Logistics
- **CLI Commands:** `bliss start`, `bliss panic`, `bliss config`, `bliss status`.
- **Blocking layers:** `/etc/hosts` plus a pf firewall table for stronger, browser-agnostic blocking.
- **Timer daemon:** `blissd` runs in the background via launchd and unblocks when time is up.
- **Menubar:** lightweight Swift status app shows the countdown.
- **Root helper:** `blissroot` runs as a LaunchDaemon so users don’t need sudo after install.
- **Config:** `~/.config/bliss/blocks.txt` stores blocked domains.
