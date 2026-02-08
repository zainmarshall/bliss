# Bliss
Bliss is a macOS focus lock that blocks distracting websites and force‑closes selected apps. It runs a background timer, shows a menubar countdown, and makes you solve a typing challenge to escape early.

# MACOS Only. To all Windows and Linux users of Flavortown, please watch the following video demo to get a full understanding of the app! 

## Video Demo
https://github.com/user-attachments/assets/2810f783-6585-4e67-8919-b054ea23d219

## What it does

- Blocks websites via /etc/hosts + pf firewall table
- Force‑closes blocked apps during a session
- Runs a background timer (blissd) so the lock survives terminal close or reboot
- Menubar timer (always‑on status)
- Panic mode typing challenge

## Installation Instructions
1. Download and run the release installer:
  ```bash
curl -fsSL https://github.com/zainmarshall/bliss/releases/download/v0.1.0/bliss-macos-universal.zip -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```
NOTE: If you every on install see this error:
Bootstrap failed: 5: Input/output error
Try re-running the command as root for richer errors.
Just re-run the command. That should fix it.
2. Verify:
`bliss --help`
4. Configure it:
`bliss config website add <DOMAIN OF WEBSITE TO BLOCK>`
`bliss config app add` - Will open a menu to select which apps to block
`bliss config website list` `bliss config app list` - List blocked apps
NOTE: Bliss comes with nothing configured by default, like no apps and websites blocked, so if you start it from the start it'll block nothing and throw an error. Make sure you configure it. 
- `bliss config app add` (This will open a menu for you to select apps)
- `bliss config browser add` (This will open a menu for you to select browsers to close on start)
- `bliss start <minutes>`

Commands

- bliss start <minutes> - Starts a timer for <minutes> minutes
- bliss panic - Escape a block early by completing a typing challenge.
- bliss status - Status of the timer and pf table
- bliss repair - Repair the root helper and clear state (requires sudo)
- bliss uninstall - Uninstalls everything. Must run with sudo. Requires a typing challenge. 
- bliss config website add/remove <domain> - Add or remove websites from block
- bliss config website list - list blocked websites
- bliss config app add/remove - Opens a menu to select apps to add / remove from the block
- bliss config app list - list blocked apps
- bliss config browser add/remove - Opens a menu to select browsers to close on start
- bliss config browser list - list extra browsers to close
- bliss config quotes short/medium/long/huge - Configure the length of quotes used in the typing challenges. 

Notes
- Starting a session closes browsers and resets web connections. Save your work first.

## Architecture & Logistics
- **CLI Commands:** `bliss start`, `bliss panic`, `bliss config`, `bliss status`.
- **Blocking layers:** `/etc/hosts` plus a pf firewall table for stronger, browser-agnostic blocking.
- **Timer daemon:** `blissd` runs in the background via launchd and unblocks when time is up.
- **Menubar:** lightweight Swift status app shows the countdown.
- **Root helper:** `blissroot` runs as a LaunchDaemon so users don’t need sudo after install.
- **Config:** `~/.config/bliss/blocks.txt` stores blocked domains.

## Devlogs
Read the devlogs at: https://flavortown.hackclub.com/projects/11291 
