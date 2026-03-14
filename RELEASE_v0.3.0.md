v0.3.0 is the version of Bliss with a GUI!! It was a requested feature upon the ship of v0.1.0, so now it is here! (Ignore v0.2.0 we don't talk about that...)
The GUI is a huge improvement, a setup wizard, easier config, and a new panic mode of competitive programing problems!

### The GUI
Bliss now has a full native SwiftUI GUI. Two tabs: Session (big timer, start/panic buttons) and Settings (looks like Apple System Settings). Blocked apps and browsers render their real macOS icons which looks really nice. Keyboard shortcuts for everything — Cmd+1/2 for tabs, Cmd+, for settings, Cmd+E to panic. The CLI and GUI are now fully synced — `bliss panic` in terminal opens the GUI panic sheet via a `bliss://` URL scheme.

### Setup Wizard
When you first open the app you get a 7-step onboarding wizard: welcome, block websites (with suggestion chips for youtube, twitter, reddit, etc), block apps, add browsers, pick your panic mode, configure difficulty/length, and a summary showing everything you set up.

### Competitive Programming Panic Mode
Instead of just typing a quote, you can now be forced to solve a real CSES algorithm problem to escape. 50 problems across 3 difficulties, a local test judge, and a code editor right in the app. Supports C++17, Python 3, Java 17, and Zen++. Everything runs locally — no internet needed.

### Config Menu Redesign
Migrated to Apple's `.formStyle(.grouped)` so it actually looks like a real settings menu. All dropdowns aligned, keyboard shortcuts reference section, and uninstalling requires a panic challenge.

### Under the Hood
Migrated from Codeforces to CSES for the problem bank. Built a LaTeX math renderer for problem statements. Universal binaries (arm64 + x86_64). No build tools needed for install.

### Install
```bash
curl -fsSL \
  "https://github.com/zainmarshall/bliss/releases/download/v0.3.0/bliss-macos-universal.zip" \
  -o /tmp/bliss.zip && \
  rm -rf /tmp/bliss && mkdir -p /tmp/bliss && \
  unzip -q /tmp/bliss.zip -d /tmp/bliss && \
  bash /tmp/bliss/bliss_release/scripts/install.sh
```

MACOS Only. To all Windows and Linux users of Flavortown, please watch the video demo in the GitHub readme!

Hope you guys enjoy!
