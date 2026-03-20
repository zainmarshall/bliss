## Bliss v0.5.0

Big update. Bliss now has weekly session scheduling, a completely new timer UI, config profiles with colors, and a bunch of polish.

**Scheduling** — New Schedule tab with a full 24-hour weekly calendar. Create recurring focus sessions tied to saved configs. Pick days, set a 12h time with AM/PM, choose duration. Sessions auto-start at the scheduled time. Everything color-coded by config on the calendar grid.

**Timer overhaul** — The session screen now has a big HH:MM:SS display. Type digits and they fill from the right like a microwave timer. Supports hours and exact seconds — no more rounding to the nearest minute. The CLI also accepts `bliss start 90 --seconds` now.

**Configs** — Renamed from "Profiles" to "Configs." Each config gets a color (pick from a popover swatch grid) that carries through to the schedule calendar. A default config with common social media sites is auto-created on first launch.

**Panic challenges** — All difficulty selectors now use segmented pickers. Added Wordle difficulty: Easy (6 guesses), Medium (5), Hard (4). Typing challenge now requires 100% accuracy with MonkeyType-style error highlighting.

**Ghost window fix** — Closing the window via red X or Cmd+W now hides instead of destroying. Reopening from menubar always works.

**Install script** — Colored output with numbered steps and checkmarks.

One-liner install:
```
curl -fsSL "https://github.com/zainmarshall/bliss/releases/download/v0.5.0/bliss-macos-universal.zip" -o /tmp/bliss.zip && rm -rf /tmp/bliss && mkdir -p /tmp/bliss && unzip -q /tmp/bliss.zip -d /tmp/bliss && bash /tmp/bliss/bliss_release/scripts/install.sh
```
