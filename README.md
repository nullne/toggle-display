# DisplayToggle

A tiny macOS menu-bar app to toggle displays on/off, keep the Mac awake (Caffeine mode), and remind you to take breaks.

## Features

- **Toggle displays** — turn individual displays on/off (DDC power, built-in brightness, or a blackout window fallback).
- **Caffeine mode** — prevent display sleep.
- **Break reminder** — after a configurable amount of continuous screen time (default 45 min), a reminder window appears; if you keep going, it re-appears and escalates every few minutes. Locking the screen for over a minute resets the timer. The menu-bar icon gradually fills with color as time passes, turns orange when it's time, and pulses red when overdue.

## Install

Via [Homebrew](https://brew.sh):

```sh
brew install --cask nullne/tap/displaytoggle
```

> The app is ad-hoc signed (not notarized), so Gatekeeper will block it the first time. Either **right-click the app → Open** once, or clear the quarantine flag:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/DisplayToggle.app
> ```

## Build from source

```sh
swift build -c release          # build
swift test                      # run tests
bash Scripts/build.sh           # produce dist/DisplayToggle.app
bash Scripts/create-dmg.sh      # produce dist/DisplayToggle.dmg
```

Requires macOS 14+ and a Swift 5.10+ toolchain.

## Releasing

Releases are fully automated by GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)). To cut a release, just push a version tag:

```sh
git tag v1.2.3
git push origin v1.2.3
```

On a `v*` tag the workflow builds the app, packages `DisplayToggle-<version>.dmg`, publishes a GitHub Release with it, and updates the Homebrew cask in [`nullne/homebrew-tap`](https://github.com/nullne/homebrew-tap) (bumping `version` and `sha256`). Users then get it with `brew upgrade --cask displaytoggle`.

The tap update requires a repo secret `TAP_GITHUB_TOKEN` — a fine-grained PAT with **Contents: read and write** on `nullne/homebrew-tap`.
