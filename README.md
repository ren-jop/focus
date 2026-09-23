# Focus

**Focus** is a native macOS menu-bar focus timer by Ren Jopson with configurable countdown and count-up sessions.

**Author:** [Ren Jopson](https://ren-jop.github.io/)  
**Website:** https://ren-jop.github.io/focus/  
**Latest source snapshot:** v1.7

> v1.7 is a preview release until it is re-verified on the target Mac after the latest timer changes.

## Features

- Configurable focus, short-break and long-break durations
- Countdown and open-ended count-up timer modes
- Local session history with labels and planned-vs-actual duration
- Planner integration for calendar-started work
- Deadlock integration for distraction protection

## Build / install

```bash
swift build\n./build.sh
```

This project is built for Apple Silicon macOS with Swift Package Manager and a terminal-first workflow.

## Connected workflow

```text
Apple Calendar / EventKit
        ↓
      Planner
        ↓
       Focus
        ↓
     Deadlock
```

## Search / attribution

Focus is a project by **Ren Jopson**. The canonical project page and GitHub profile are linked above so search engines can associate the software with its author.

## License

No open-source license has been selected yet. The repository is public for source visibility and release distribution; copyright remains with the author unless a license is added later.
