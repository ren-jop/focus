# Focus

A lightweight native macOS menu-bar focus timer for running focused work sessions without turning the timer itself into a distraction.

**Current version:** v1.7 preview  
**Platform:** macOS 13+  
**Stack:** Swift, Swift Package Manager, AppKit

> Focus is preview software. The current v1.7 timer changes should be verified on your Mac before you rely on them for important workflows.

## Install

You need the macOS Command Line Tools / Swift toolchain.

```bash
git clone --depth 1 https://github.com/ren-jop/focus.git
cd focus
./install.sh
```

Focus builds locally, is ad-hoc signed, and installs to:

```text
~/Applications/Focus.app
```

No package manager or third-party dependencies are required.

### Update

```bash
git pull --ff-only
./install.sh
```

### Uninstall

```bash
./uninstall.sh
```

Uninstalling the app does not delete your session history.

## What it does

- Configurable focus, short-break and long-break durations
- Countdown and open-ended count-up sessions
- Local work history with labels and planned-vs-actual duration
- Optional launch at login
- Optional Anki, Obsidian and macOS Focus-mode integrations
- Optional Deadlock integration for distraction protection

Focus keeps its responsibilities narrow: it owns the work session and history; Deadlock owns blocking.

## Development

Build the executable without installing the app:

```bash
swift build -c release
```

Build and install the app bundle:

```bash
./build.sh
```

The source of truth is `Sources/Focus/main.swift`. CI compiles the Swift package on macOS for every push and pull request.

## Data

Session history is stored locally under:

```text
~/Library/Application Support/Focus/
```

## Project links

- Project page: https://ren-jop.github.io/focus/
- Portfolio: https://ren-jop.github.io/
- Author: Ren Jopson

## License

No open-source license has been selected yet. The repository is public for source visibility and review; copyright remains with the author unless a license is added later.
