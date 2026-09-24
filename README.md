# Focus

A small native macOS timer for focused work.

**Status:** v1.7 preview  
**Platform:** macOS 13+  
**Stack:** Swift, AppKit, SwiftPM

## Why

I wanted a timer that was fast to start and small enough that it did not become another productivity system to manage.

## Install

```bash
git clone --depth 1 https://github.com/ren-jop/focus.git
cd focus
./install.sh
```

Focus installs to:

```text
~/Applications/Focus.app
```

## What it does

- Countdown sessions.
- Open-ended count-up sessions.
- Configurable focus and break durations.
- Local work history.
- Labels and planned-vs-actual duration.
- Optional launch at login.
- Optional Anki, Obsidian and macOS Focus integrations.
- Optional Deadlock integration for distraction blocking.

Focus owns the active work session. It does not own the calendar or Deadlock's blocking policy.

## Data

Session history is stored locally under:

```text
~/Library/Application Support/Focus/
```

## Update

```bash
git pull --ff-only
./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

Uninstalling the app does not delete session history.

## Development

```bash
swift build -c release
./build.sh
```

CI builds the Swift package on macOS.

## License

No open-source license has been selected yet.
