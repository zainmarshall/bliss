# v1.0.0 Devlog I: Linux Time!!

Its finally time to add Linux support! So on the macOS version I wrote it in Swift so it would be native and super fast, and I didn't want to use electron as its slow, so for the cross platform I decided to rewrite the GUI to Tauri so it can support macOS, now Linux, and later Windows!

**Platform-abstracting the C++ backend: firewall, DNS flush, and process management.**

---

## What changed

---

### 1. Linux firewall implementation
![Feature](https://img.shields.io/badge/Feature-iptables-orange?style=for-the-badge)

- Created `src/firewall_linux.cpp` - a full iptables/ip6tables implementation that mirrors the macOS pfctl behavior.
- Works by creating a dedicated `bliss` chain, resolving blocked domains to IPs, and inserting REJECT rules for each one. IPv4 and IPv6 handled separately.
- Wrapped the original `firewall_block.cpp` in `#ifdef __APPLE__` so it only compiles on macOS.
- On modern distros (Debian 11+, Ubuntu 22.04+, Fedora 30+), nftables runs under the hood but the `iptables-nft` compat shim means these exact commands still work.

---

### 2. DNS cache flush
![System](https://img.shields.io/badge/System-DNS-indigo?style=for-the-badge)

- Platform-guarded `flush_dns()` in `hosts_block.cpp` - macOS still uses dscacheutil + mDNSResponder, Linux now tries `resolvectl flush-caches`, falls back to the older `systemd-resolve --flush-caches`, and also pokes `nscd` for legacy setups.
- All three paths fail silently if unavailable, so it degrades gracefully no matter what init system or resolver the distro uses.

---

### 3. Browser killing
![Feature](https://img.shields.io/badge/Feature-Process_Mgmt-blue?style=for-the-badge)

- `kill_browser_apps()` now works cross-platform - Linux just uses `pkill -x` directly (same as macOS minus the `.app` bundle weirdness).
- The macOS-only "reopen after kill" behavior (`open -a`) is guarded behind `#ifdef __APPLE__` since there's no universal equivalent on Linux desktop environments.
- `get_console_uid()` and `reopen_app_as_user()` are now macOS-only helpers.

---

### 4. Build system
![System](https://img.shields.io/badge/System-CMake-green?style=for-the-badge)

- `CMakeLists.txt` now picks the right firewall source per platform - `firewall_block.cpp` on macOS, `firewall_linux.cpp` on Linux.
- macOS build verified clean, all tests still pass.
- Best way to test: Ubuntu 24.04 in UTM (Apple Silicon) or VirtualBox. Docker works for compile checks but iptables needs `--privileged`.

---

**Next up:** Platform-abstract the daemon - systemd service files instead of launchd plists, and reworking the root helper socket.

---
---

# v1.0.0 Devlog II: Tauri GUI Scaffold

The SwiftUI GUI was ~8,900 lines and macOS-only. This session sets up the Tauri + Svelte replacement with the core session flow working end-to-end.

**Scaffolding the cross-platform GUI: timer, session start, and typing panic challenge.**

---

## What changed

---

### 1. Tauri + Svelte project setup
![Framework](https://img.shields.io/badge/Framework-Tauri_v2-orange?style=for-the-badge)

- Initialized a Tauri v2 app inside the existing repo (`src-tauri/` for Rust, `ui/` for Svelte).
- Svelte 5 with runes (`$state`, `$derived`) - no legacy reactivity.
- Vite builds the frontend to `dist/`, Tauri serves it in a native webview.
- Same `bliss` CLI binary under the hood - the Tauri Rust backend just shells out to it, exactly like the Swift GUI did with `BlissCommandRunner`.

---

### 2. Session timer with digit entry
![Feature](https://img.shields.io/badge/Feature-Timer-blue?style=for-the-badge)

- Reads `/var/db/bliss_end_time` every second from Rust, same file the Swift menubar read.
- Countdown displays as `HH:MM:SS` in a big rounded font, orange pulsing animation in the last minute.
- When no session is active, you get the same right-to-left digit entry as the Swift version - just type numbers and they fill in from the right.
- Start button calls `bliss start <minutes>` through the Rust backend.

---

### 3. Typing panic challenge
![Feature](https://img.shields.io/badge/Feature-Panic-red?style=for-the-badge)

- Loads a random quote from `quotes.txt` (tries `~/.config/bliss/quotes.txt` first, falls back to repo root).
- Character-by-character coloring: green for correct, red+underline for wrong, grey for untyped. Same MonkeyType-style feel as the Swift version.
- Progress bar turns green at 100% accuracy. Submit calls `bliss panic --skip-challenge` since the challenge was already completed in the GUI.
- Hidden textarea trick for capturing keystrokes while showing the styled quote display.

---

### 4. Dark minimal UI
![Design](https://img.shields.io/badge/Design-Dark_Minimal-gray?style=for-the-badge)

- Dark grey background (#1a1a1a), light text, no decorative elements.
- Matches the feel of the Swift version - centered layout, big timer, clean buttons.
- SF Pro / system font stack so it looks native on macOS and reasonable on Linux (falls back to system sans-serif).

---

**Next up:** Tab navigation (Session/Settings), blocked sites/apps config UI, and menubar tray with countdown.

