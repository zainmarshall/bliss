# Bliss v0.3.0 Development Log

## 2026-03-13: Setup Wizard, Tab Rewrite, App Icons, and Release Polish

v0.3.0 is the first proper release-ready version of Bliss. The GUI got a near-complete rewrite — most of the work went into ContentView.swift (~930 lines, rewritten 3+ times) and CodeforcesPanic.swift (~720 lines). If a human were writing all the v0.3.0 features from scratch, this would be roughly 12-16 hours of raw coding time.

### Setup Wizard (7 steps)
Built a first-run onboarding wizard that completely replaces the main app until setup is done (no blur overlay — the tab content literally doesn't exist in the view hierarchy). Steps: Welcome, Block Websites (with suggestion chips for youtube/twitter/reddit/etc), Block Apps, Browsers, Panic Challenge Type, Challenge Config (quote length or CSES difficulty depending on mode), and a summary page. The summary shows counts: X websites to block, Y apps to block, Z browsers to restart, plus your challenge config. All settings are applied atomically on "Get Started."

### TabView Killed
Replaced SwiftUI's `TabView` with a manual tab bar + `if/else` rendering. The `TabView` was rendering both tabs simultaneously — focus rings from the Session tab's TextField and Start button bled through to Settings, and pressing Enter on Settings would start a session. The fix was simple: only the active tab exists in the view hierarchy now. Custom tab bar buttons with generous hit targets.

### App & Browser Icons
Blocked apps in both the settings form and wizard now show their real macOS app icons via `NSWorkspace.shared.icon(forFile:)`. Browsers show their icons too, resolved by bundle ID (Safari, Chrome, Firefox, Brave, Arc, Edge, Opera, Vivaldi all mapped). Falls back to SF Symbols if the icon can't be found.

### Settings Redesign
`Form` with `.formStyle(.grouped)` for a native System Settings look. Aligned dropdown pickers at 250pt. Added keyboard shortcut reference section, browser restart explanation footer. Uninstall requires completing a panic challenge.

### Competitive Programming
Added Zen++ language support. Cleaned up the code editor (removed fake traffic lights, now a proper embedded editor with monospace font and subtle border). Extracted sub-views to fix Swift type-checker timeouts on x86_64. ScrollView with pinned Cancel header.

### CLI Integration
`bliss://` URL scheme so `bliss panic` in terminal opens the GUI panic sheet. Keyboard shortcuts: Cmd+1/2 for tabs, Cmd+, for settings, Cmd+E for panic.

### Release Cleanup
Bumped all version strings to 0.3.0 (Info.plist in install.sh, run_gui.sh, build artifacts). Removed hardcoded dev paths from BlissCommandRunner, menubar, and CodeforcesPanic. Universal binaries (arm64 + x86_64) for all components. Install script skips build tools when prebuilt binaries exist.

### Most Edited Files
1. **gui/ContentView.swift** (~930 LOC) — rewritten 3+ times. Setup wizard, tab system, settings form, app icons, keyboard shortcuts. ~6-8 hrs human time.
2. **gui/CodeforcesPanic.swift** (~720 LOC) — Zen++ support, editor styling, sub-view extraction, LaTeX renderer. ~3-4 hrs.
3. **gui/BlissViewModel.swift** (~520 LOC) — setup completion, config sync, refresh logic. ~1-2 hrs.
4. **src/main.cpp** (~1430 LOC) — URL scheme integration, panic mode routing. ~30 min.
5. **scripts/*.sh** — version bumps, Info.plist URL scheme, install logic. ~30 min.

Total codebase: ~5,100 lines across 13 source files (8 Swift, 5 C++).

---

# Bliss v0.2.0 Development Log

## 2026-03-11: GUI Release Prep

### Renamed Codeforces -> Competitive Programming
- Switched from Codeforces problems (which don't release full test cases) to **CSES Problem Set** (cses.fi) which provides full test cases on every problem
- Created a CSES scraper (`tools/problem_bank/fetch_cses.py`) that pulls problem statements, I/O descriptions, constraints, and sample tests
- Populated `problems/problems.json` with **50 CSES problems**: 25 easy (introductory + sorting/searching), 19 medium (DP + graph), 6 hard (trees)
- All struct/enum names updated: `CFPanic*` -> `CPPanic*`, `CFPanicDifficulty` -> `CPDifficulty`
- Backwards compat: old "codeforces" config value auto-maps to "competitive"

### LaTeX / Math Rendering
- Added `MathRenderer.render()` for converting LaTeX math notation to Unicode in problem statements
- Supports: subscripts (a₁), superscripts (10⁵), comparison operators (≤ ≥ ≠), dots (…), arrows (→), floor/ceil (⌊⌋), set operations (∈ ∪ ∩), and more
- Applied to problem statement, input spec, output spec, and constraints display

### Bug Fixes
- **"Problem bank or language presets not found"**: Problem JSON couldn't be found from GUI because candidate paths didn't include the dev directory. Added hardcoded dev path and `problems.json` as primary filename alongside legacy `codeforces.json` fallback.
- **Add apps/browsers does nothing**: Race condition in SwiftUI `fileImporter` — the binding's `set` closure fires before the result handler, nil-ing out `importTarget`. Fixed with a `pendingImportTarget` that captures the value before dismissal.
- **CLI "command not found" after error**: Error messages now show the full binary path instead of bare `bliss` (e.g., `sudo /Users/zain/Developer/bliss/build/bliss repair`).
- **Menubar install under sudo**: `launchctl bootstrap` failed because `id -u` returned 0 (root) under sudo. Fixed to use `$SUDO_UID` for the real user's GUI domain. Also resolved `$HOME` pointing to `/var/root` under sudo by looking up the real user's home via `dscl`.

### CLI / GUI Sync
- CLI `panic` command now reads `~/.config/bliss/panic_mode.txt`
- If mode is "competitive", CLI opens BlissGUI.app instead of running a terminal typing test
- Falls back to typing test if GUI app isn't found

### GUI Redesign (Config Tab)
- **Panic settings section**: Mode picker is now first (was middle). Shows relevant sub-option only: quote length for typing mode, problem difficulty for competitive mode. Each option has a description label explaining what it does.
- **Blocked Websites**: Add domain input moved inside the group box at the bottom (was floating above, confusing). Consistent with apps/browsers pattern.
- **All lists**: Consistent layout — entries listed first, divider, then add button at bottom. Remove buttons styled as borderless red text.
- **Group boxes**: Each has an SF Symbol icon label + subtitle explaining its purpose.
- **Uninstall button**: Added at bottom of config. Requires completing a panic challenge (typing or competitive) before uninstalling — keeps it hard to remove on impulse. Uninstall also kills the GUI and menubar processes.

### Infrastructure
- Version bumped to `0.2.0` in build scripts
- `install.sh` now copies all `problems/*.json` files
- `run_gui.sh` copies problems into app bundle Resources directory

### Files Changed
- `gui/CodeforcesPanic.swift` — full rewrite: renamed types, added MathRenderer, CSES paths, constraints field, better error display
- `gui/ContentView.swift` — config tab redesign, uninstall button, fileImporter fix
- `gui/BlissViewModel.swift` — renamed enums/vars, backwards compat for config, uninstall function, better error messages
- `gui/PanicChallengeView.swift` — updated type references
- `src/main.cpp` — panic mode config reading, open GUI for competitive mode, help text
- `scripts/install.sh` — version bump, copy all problem JSON files
- `scripts/run_gui.sh` — version bump, copy problems into bundle
- `scripts/install_menubar.sh` — sudo UID/HOME fix for launchctl

### New Files
- `problems/problems.json` — 50 CSES problems (easy/medium/hard)
- `tools/problem_bank/fetch_cses.py` — CSES problem scraper
