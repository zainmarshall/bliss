## Overview
Bliss is a productivity app, itll block apps on your computer and make it super super hard to escape, but of course we need a panic mode in case something bad truly occurs, so there is one route to esacpe and that is through our built in panic mode.s

## Architecture
CLI applications where you can run commands like:
bliss start X 
bliss panic
bliss config

## Overall flow
User runs: bliss start X
↓
Enable lock down mode
↓
Block websites using etc hosts
↓
Use AppleScript to kill all blocked apps
↓
Have a timer running in the background
↓
User enables panic mode to break early
↓
Panic mode challenge (typing test? codeforces / leetcode?)
↓
Sucsess 
↓ 
Remove block        

## Tech Stack
Language: my competetive programming goat c++
TUI
MacOS