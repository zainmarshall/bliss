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

---
---

# v1.0.0 Devlog III: Settings & Configs

**Full settings panel with config profiles, app icons, file pickers, and Lucide icons.**

---

## What changed

---

### 1. Settings panel
![Feature](https://img.shields.io/badge/Feature-Settings-blue?style=for-the-badge)

- Sidebar + detail layout matching the SwiftUI version. Seven sections in the same order: Configs, Panic Challenge, Blocked Websites, Blocked Apps, Browsers, Troubleshooting, Uninstall.
- Icons from Lucide (Folder, ShieldAlert, Globe, LayoutGrid, Compass, Wrench, Trash2) instead of SF Symbols.
- Blocked websites has preset packs (Social Media, Entertainment, News, Gaming, Shopping) that toggle green when active. Apps and browsers show real icons extracted from .app bundles via `sips`.

---

### 2. Config profiles
![Feature](https://img.shields.io/badge/Feature-Configs-purple?style=for-the-badge)

- Save current websites/apps/browsers/panic settings as a named config. Configs stored as JSON in `~/.config/bliss/profiles/`.
- Apply swaps everything at once - clears current config and loads the profile's. Active config highlighted with color dot.
- Simpler flow than SwiftUI - no color picker, just save/apply/delete.

---

### 3. Native file pickers
![System](https://img.shields.io/badge/System-Dialog-green?style=for-the-badge)

- "Add App..." and "Add Browser..." open native macOS file dialogs via `tauri-plugin-dialog`, filtered to `.app` bundles. Same UX as the SwiftUI `fileImporter`.
- App icons extracted server-side in Rust: reads `CFBundleIconFile` from Info.plist, converts `.icns` to 64x64 PNG with `sips`, sends base64 to the frontend. Browser icons resolved via `mdfind` bundle ID lookup.

---

**Next up:** Schedule tab, statistics tab with activity heatmap, and system tray menubar.

---
---

# v1.0.0 Devlog IV: All Panic Modes

**Ported all 8 panic challenges from SwiftUI to Tauri - plus a mini IDE for competitive programming.**

---

## What changed

---

### 1. Game challenges
![Feature](https://img.shields.io/badge/Feature-Panic_Games-red?style=for-the-badge)

- Minesweeper (flood-fill, first-click safe, right-click flags), Wordle (color-coded feedback, on-screen keyboard, shake on invalid), 2048 (arrow key sliding, merge logic, classic tile colors), Sudoku (backtracking generator, conflict highlighting, numpad + keyboard), Simon Says (animated sequence playback, color grid, replay on wrong).
- Pipes uses the same Hamiltonian path + flood-fill partitioning algorithm as the Swift version. Drag-to-draw with SVG overlay, backtracking, falls back to snake paths if random gen fails.

---

### 2. Competitive programming IDE
![Feature](https://img.shields.io/badge/Feature-CP_IDE-purple?style=for-the-badge)

- Split-pane layout: problem statement (with LaTeX math rendering) on the left, code editor on the right.
- Syntax highlighting for C++, Python, Java - keywords, strings, comments, numbers all colored. Line numbers in gutter, tab inserts spaces.
- Rust backend loads problems from `~/.config/bliss/problems/problems.json`, compiles and runs code against test cases, diffs output. Supports clang++, python3, javac.

---

### 3. Settings and config
![Feature](https://img.shields.io/badge/Feature-Settings-blue?style=for-the-badge)

- All 8 modes in the panic dropdown with descriptions. Each mode has its own difficulty/size config via segmented controls (grid size, guess count, target tile, clue count, sequence length, flow count, problem difficulty).
- Game configs stored in localStorage, panic mode stored in `~/.config/bliss/panic_mode.txt`. Removed the orange pulsating last-minute timer animation.

---

**Next up:** Schedule tab, statistics, and system tray.

