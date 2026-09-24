# Focus

A lightweight native macOS focus timer for deliberate work.

Focus owns the active work session: it can run fixed countdowns or open-ended count-up sessions, keep local history, and accept context from Planner while asking Deadlock to protect an active session.

> **Status:** v1.7 preview. The current timer and integration changes still need broader runtime verification.

## Install

Requirements: macOS 13+ and Apple's Command Line Tools.

```bash
git clone https://github.com/ren-jop/focus.git
cd focus
./install.sh
```

The installer reconstructs the vendored v1.7 source snapshot, validates it, builds a release with Swift Package Manager, and installs:

```text
~/Applications/Focus.app
```

Remove the app while keeping history and preferences:

```bash
./uninstall.sh
```

## Engineering

- Swift + Swift Package Manager
- native menu-bar UI
- countdown and open-ended count-up timing
- adaptive timer updates to reduce unnecessary idle work
- local session history with planned-vs-actual duration
- Unix-socket IPC for optional Deadlock protection
- Planner metadata handoff without competing timer ownership

## System boundary

```text
Apple Calendar
      │
   Planner
      │ context
      ▼
    Focus ─────► local history
      │
      └────────► Deadlock IPC
```

Planner can start a session and Deadlock can protect it, but Focus remains the single owner of session timing.

## Source snapshot

The validated v1.7 preview snapshot is vendored under `source/` as base64-encoded ZIP data. `install.sh` reconstructs and verifies it before building. A notarized binary distribution is not published yet.

## Links

- Project page: https://ren-jop.github.io/focus/
- Deadlock: https://github.com/ren-jop/deadlock
- Planner: https://github.com/ren-jop/planner

## License

No open-source license has been selected. The repository is public for source visibility and release distribution; copyright remains with the author unless a license is added later.
