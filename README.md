# Bliss
Bliss is a macOS focus lock that blocks distracting websites and force‑closes selected apps. It runs a background timer, shows a menubar countdown, and makes you solve a typing challenge to escape early.

## What it does

- Blocks websites via /etc/hosts + pf firewall table
- Force‑closes blocked apps during a session
- Runs a background timer (blissd) so the lock survives terminal close or reboot
- Menubar timer (always‑on status)
- Panic mode typing challenge

## Quick start

- Install using this command `echo "Hello World"`
- bliss config website add <domain>
- bliss config app add (This will open a menu for you to select apps)
- bliss start 25

Commands

- bliss start <minutes>
- bliss panic
- bliss status
- bliss uninstall
- bliss config website add/remove/list
- bliss config app add/remove/list

## Architecture & Logistics
- **CLI Commands:** `bliss start`, `bliss panic`, `bliss config`, `bliss status`.
- **Blocking layers:** `/etc/hosts` plus a pf firewall table for stronger, browser-agnostic blocking.
- **Timer daemon:** `blissd` runs in the background via launchd and unblocks when time is up.
- **Menubar:** lightweight Swift status app shows the countdown.
- **Root helper:** `blissroot` runs as a LaunchDaemon so users don’t need sudo after install.
- **Config:** `~/.config/bliss/blocks.txt` stores blocked domains.
