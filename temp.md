## Bliss v0.5.0 Devlog

### Ghost Window Fix
- Menubar "Open Bliss" no longer shows an empty window — intercepts close with `orderOut` instead of actually closing, keeping SwiftUI's view tree alive

### Scheduling
- New Schedule tab with 24h weekly calendar grid and schedule list
- Create schedules tied to saved configs — auto-triggers sessions at the set day/time
- 12-hour time picker with AM/PM, day-of-week toggles, click-to-type digit editing

### Config System
- Renamed "Profiles" → "Configs" across the UI
- Color picker per config — popover swatch grid, colors carry through to schedule blocks on the calendar
- Auto-creates a "Default" config with common social media sites on first launch

### Timer UI
- Replaced text field with a big `--:--` display, right-to-left digit entry like a microwave timer
- Typed digits shift in from the right, backspace removes last digit, Enter starts session
- Same display becomes the live countdown during active sessions

### Typing Panic
- 100% accuracy required (was 95%), larger text, no background box
- Wrong characters show underlined in red, extra chars get red background (MonkeyType-style)

### Install Script
- Colored output with numbered steps, checkmarks, and a clean summary
