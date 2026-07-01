# DisplayToggle

A tiny macOS menu-bar app to toggle displays on/off, keep the Mac awake (Caffeine mode), and remind you to take breaks.

## Features

- **Toggle displays** — turn individual displays on/off (DDC power, built-in brightness, or a blackout window fallback).
- **Caffeine mode** — prevent display sleep.
- **Break reminder** — after a configurable amount of continuous screen time (default 45 min), a reminder window appears; if you keep going, it re-appears and escalates every few minutes. Locking the screen for over a minute resets the timer. The menu-bar icon gradually fills with color as time passes, turns orange when it's time, and pulses red when overdue.

## Install

Via [Homebrew](https://brew.sh):

```sh
brew install --cask --no-quarantine nullne/tap/displaytoggle
```

> `--no-quarantine` is needed because the app is ad-hoc signed (not notarized). Alternatively, install without it and right-click the app → **Open** the first time.

## Build from source

```sh
swift build -c release          # build
swift test                      # run tests
bash Scripts/build.sh           # produce dist/DisplayToggle.app
bash Scripts/create-dmg.sh      # produce dist/DisplayToggle.dmg
```

Requires macOS 14+ and a Swift 5.10+ toolchain.
