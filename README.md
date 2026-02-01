# Bliss

Bliss is a productivity lock for macOS. It blocks distracting websites and makes escape difficult unless you pass a built-in challenge.

## Architecture & Logistics
- **CLI-first:** `bliss start`, `bliss panic`, `bliss config`, `bliss status`.
- **Blocking layers:** `/etc/hosts` plus a pf firewall table for stronger, browser-agnostic blocking.
- **Timer daemon:** `blissd` runs in the background via launchd and unblocks when time is up.
- **Menubar:** lightweight Swift status app shows the countdown.
- **Root helper:** `blissroot` runs as a LaunchDaemon so users don’t need sudo after install.
- **Config:** `~/.config/bliss/blocks.txt` stores blocked domains.
