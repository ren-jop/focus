import AppKit
import CoreAudio
import IOKit.pwr_mgt
import ServiceManagement
import UniformTypeIdentifiers

// ---- Config (edit, then rebuild) ----
let focusMinutes = 25
let shortBreakMinutes = 5
let longBreakMinutes = 15
let longBreakEvery = 4
/// Weekday auto-start times, 24h. Empty array = no schedule (default: off).
let schedule: [(hour: Int, minute: Int)] = []
/// One dim line at the top of the menu.
let lines = [
    "one thing at a time.",
    "begin before you feel ready.",
    "attention is the work.",
    "quiet is a skill.",
]
let minWhyLength = 10

// ---- Integrations (set to false / "" to turn one off) ----
let deadlockBlocksDuringFocus = true
let deadlockExecutable = "/Applications/deadlock.app/Contents/MacOS/deadlock"
let keepAwakeDuringFocus = true
/// Names of two Shortcuts you create ("Set Focus" action: Do Not Disturb on / off).
let focusOnShortcut = "Focus On"
let focusOffShortcut = "Focus Off"
/// Open Anki when a break starts (due count in the menu needs the AnkiConnect add-on).
let ankiOnBreak = true
/// Pause whatever is playing when a break starts; resume when the next focus starts.
let musicPausesOnBreak = true

// ---- Shared bits ----
let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)   // SF Mono

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct Answer { var why: String?; var rating: Int?; var improve: String }

enum FocusTimerMode: String {
    case countdown
    case countUp

    var menuLabel: String {
        switch self {
        case .countdown: return "countdown"
        case .countUp: return "count up"
        }
    }
}

struct TimerSettings {
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let longBreakEvery: Int
    let mode: FocusTimerMode
}

final class TimerSettingsPrompt {
    private static func numberField(_ value: Int, frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.stringValue = String(value)
        field.alignment = .right
        field.font = NSFont.monospacedDigitSystemFont(
            ofSize: 12,
            weight: .regular
        )
        return field
    }

    private static func label(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }

    static func run(current: TimerSettings) -> TimerSettings? {
        let alert = NSAlert()
        alert.messageText = "Timer settings"
        alert.informativeText =
            "Changes apply to the next focus/break. Count up runs until you finish it manually."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 185))

        let mode = NSSegmentedControl(
            labels: ["Countdown", "Count Up"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        mode.frame = NSRect(x: 128, y: 151, width: 205, height: 24)
        mode.selectedSegment = current.mode == .countUp ? 1 : 0

        let focus = numberField(
            current.focusMinutes,
            frame: NSRect(x: 238, y: 112, width: 64, height: 24)
        )
        let shortBreak = numberField(
            current.shortBreakMinutes,
            frame: NSRect(x: 238, y: 80, width: 64, height: 24)
        )
        let longBreak = numberField(
            current.longBreakMinutes,
            frame: NSRect(x: 238, y: 48, width: 64, height: 24)
        )
        let every = numberField(
            current.longBreakEvery,
            frame: NSRect(x: 238, y: 16, width: 64, height: 24)
        )

        view.addSubview(label("Focus mode", frame: NSRect(x: 0, y: 154, width: 110, height: 20)))
        view.addSubview(mode)

        view.addSubview(label("Focus length", frame: NSRect(x: 0, y: 115, width: 150, height: 20)))
        view.addSubview(focus)
        view.addSubview(label("min", frame: NSRect(x: 307, y: 115, width: 35, height: 20)))

        view.addSubview(label("Short break", frame: NSRect(x: 0, y: 83, width: 150, height: 20)))
        view.addSubview(shortBreak)
        view.addSubview(label("min", frame: NSRect(x: 307, y: 83, width: 35, height: 20)))

        view.addSubview(label("Long break", frame: NSRect(x: 0, y: 51, width: 150, height: 20)))
        view.addSubview(longBreak)
        view.addSubview(label("min", frame: NSRect(x: 307, y: 51, width: 35, height: 20)))

        view.addSubview(label("Long break every", frame: NSRect(x: 0, y: 19, width: 150, height: 20)))
        view.addSubview(every)
        view.addSubview(label("sessions", frame: NSRect(x: 307, y: 19, width: 55, height: 20)))

        alert.accessoryView = view

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        func clamped(_ field: NSTextField, default fallback: Int, _ range: ClosedRange<Int>) -> Int {
            let parsed = Int(field.stringValue.trimmed) ?? fallback
            return min(range.upperBound, max(range.lowerBound, parsed))
        }

        return TimerSettings(
            focusMinutes: clamped(focus, default: current.focusMinutes, 1...720),
            shortBreakMinutes: clamped(shortBreak, default: current.shortBreakMinutes, 1...120),
            longBreakMinutes: clamped(longBreak, default: current.longBreakMinutes, 1...240),
            longBreakEvery: clamped(every, default: current.longBreakEvery, 1...12),
            mode: mode.selectedSegment == 1 ? .countUp : .countdown
        )
    }
}

struct Entry: Codable {
    let date: Date
    let kind: String        // "stopped" | "completed"
    let minutes: Int
    let why: String?
    let rating: Int?
    let improve: String?
    let label: String?
    let calendarEventID: String?
    let plannedMinutes: Int?
}

/// ~/Library/Application Support/Focus/log.jsonl  (one JSON object per line)
var logURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Focus/log.jsonl")
}

func appendLog(_ e: Entry) {
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    guard var data = try? enc.encode(e) else { return }
    data.append(0x0A)
    if let h = try? FileHandle(forWritingTo: logURL) {
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}

/// Appends a short markdown entry to the Obsidian note the user picked (if any).
func appendNote(_ e: Entry) {
    guard let path = UserDefaults.standard.string(forKey: "note"),
          FileManager.default.fileExists(atPath: path) else { return }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    var s = "**\(f.string(from: e.date))** · "
    if let label = e.label, !label.isEmpty {
        s += "**\(label)** · "
    }
    s += e.kind == "stopped" ? "stopped after \(e.minutes)m" : "\(e.minutes)m focus"
    if let r = e.rating { s += " · \(r)/5" }
    s += "\n"
    if let w = e.why { s += "- why: \(w)\n" }
    if let i = e.improve { s += "- next time: \(i)\n" }

    let url = URL(fileURLWithPath: path)
    guard let h = try? FileHandle(forUpdating: url) else { return }
    defer { try? h.close() }

    let end = (try? h.seekToEnd()) ?? 0
    var endsWithNewline = false
    if end > 0 {
        try? h.seek(toOffset: end - 1)
        endsWithNewline = (try? h.read(upToCount: 1))?.first == 0x0A
    }
    _ = try? h.seekToEnd()

    let chunk = (endsWithNewline ? "\n" : "\n\n") + s
    if let d = chunk.data(using: .utf8) {
        try? h.write(contentsOf: d)
    }
}

/// Runs a macOS Shortcut by name (used for Do Not Disturb on/off).
func runShortcut(_ name: String) {
    guard !name.isEmpty else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    p.arguments = ["run", name]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
}

/// True if the default output device is currently running (something is playing audio).
func audioIsPlaying() -> Bool {
    var dev = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr
    else { return false }
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                      mScope: kAudioObjectPropertyScopeGlobal,
                                      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

/// Sends the keyboard play/pause media key (Firefox handles it for Apple Music web).
func sendPlayPause() {
    func post(_ down: Bool) {
        let flags = down ? 0xA00 : 0xB00
        let data1 = (16 << 16) | flags          // 16 = NX_KEYTYPE_PLAY
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                           timestamp: 0, windowNumber: 0, context: nil,
                           subtype: 8, data1: data1, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
    post(true)
    post(false)
}

/// Cards due in Anki via the AnkiConnect add-on.
/// This stays asynchronous so opening the menu never blocks on localhost I/O.
func fetchAnkiDue(_ completion: @escaping (Int?) -> Void) {
    var req = URLRequest(
        url: URL(string: "http://127.0.0.1:8765")!,
        timeoutInterval: 0.5
    )
    req.httpMethod = "POST"
    req.httpBody = #"{"action":"findCards","version":6,"params":{"query":"is:due"}}"#
        .data(using: .utf8)

    URLSession.shared.dataTask(with: req) { data, _, _ in
        var count: Int?
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? [Any] {
            count = result.count
        }

        DispatchQueue.main.async {
            completion(count)
        }
    }.resume()
}

/// Asks deadlock's root daemon to keep distracting websites blocked for the
/// supplied duration. The deadlock menu UI does not need to be open.
func startDeadlockDistractionBlock(
    seconds: Int,
    completion: @escaping (Bool, String?) -> Void
) {
    guard deadlockBlocksDuringFocus else {
        completion(true, nil)
        return
    }

    guard FileManager.default.isExecutableFile(atPath: deadlockExecutable) else {
        completion(false, "deadlock is not installed")
        return
    }

    DispatchQueue.global(qos: .utility).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: deadlockExecutable)
        process.arguments = ["--ipc", "focus-start", String(max(1, seconds))]

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                completion(
                    process.terminationStatus == 0,
                    (message?.isEmpty == false) ? message : nil
                )
            }
        } catch {
            DispatchQueue.main.async {
                completion(false, String(describing: error))
            }
        }
    }
}


/// Non-mutating health check used for the menu indicator.
/// A live daemon owns /var/run/deadlock.sock, so this avoids spawning a helper
/// process just to draw the menu.
func pingDeadlock(_ completion: @escaping (Bool) -> Void) {
    let ready =
        deadlockBlocksDuringFocus &&
        FileManager.default.isExecutableFile(atPath: deadlockExecutable) &&
        FileManager.default.fileExists(atPath: "/var/run/deadlock.sock")
    completion(ready)
}


// ---- Calendar/menu integration ----
struct ExternalFocusRequest: Codable {
    let seconds: Int
    let title: String?
    let calendarEventID: String?
    let plannedSeconds: Int?
    let createdAt: Date
}

let focusStartNotification = Notification.Name("local.focus.startRequested")
let focusStateNotification = Notification.Name("local.focus.stateChanged")

var focusRequestURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Focus/start-request.json")
}

func writeFocusRequest(
    seconds: Int,
    title: String?,
    calendarEventID: String?,
    plannedSeconds: Int?
) throws {
    let clamped = max(60, min(seconds, 12 * 60 * 60))
    let cleanTitle = title?.trimmed
    let cleanEventID = calendarEventID?.trimmed

    let request = ExternalFocusRequest(
        seconds: clamped,
        title: (cleanTitle?.isEmpty == false) ? cleanTitle : nil,
        calendarEventID: (cleanEventID?.isEmpty == false) ? cleanEventID : nil,
        plannedSeconds: plannedSeconds.map {
            max(60, min($0, 12 * 60 * 60))
        },
        createdAt: Date()
    )

    let dir = focusRequestURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
        at: dir,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(request)
    try data.write(to: focusRequestURL, options: .atomic)
    try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: focusRequestURL.path
    )
}

func postFocusStateNotification() {
    DistributedNotificationCenter.default().postNotificationName(
        focusStateNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

func postFocusRequestNotification() {
    DistributedNotificationCenter.default().postNotificationName(
        focusStartNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

func runFocusRequestHelperIfNeeded() -> Bool {
    let args = CommandLine.arguments

    if args.contains("--integration-check") {
        print("focus calendar/deadlock integration ready v1.7")
        return true
    }

    guard let secondsIndex = args.firstIndex(of: "--start-seconds"),
          args.indices.contains(secondsIndex + 1),
          let seconds = Int(args[secondsIndex + 1])
    else {
        return false
    }

    var title: String?
    if let titleIndex = args.firstIndex(of: "--title"),
       args.indices.contains(titleIndex + 1) {
        title = args[titleIndex + 1]
    }

    var calendarEventID: String?
    if let eventIndex = args.firstIndex(of: "--event-id"),
       args.indices.contains(eventIndex + 1) {
        calendarEventID = args[eventIndex + 1]
    }

    var plannedSeconds: Int?
    if let plannedIndex = args.firstIndex(of: "--planned-seconds"),
       args.indices.contains(plannedIndex + 1) {
        plannedSeconds = Int(args[plannedIndex + 1])
    }

    if UserDefaults.standard.string(forKey: "phase") == "focus",
       let existingDeadline = UserDefaults.standard.object(forKey: "deadline") as? Date,
       existingDeadline > Date() {
        fputs("Focus is already running.\n", stderr)
        exit(2)
    }

    do {
        try writeFocusRequest(
            seconds: seconds,
            title: title,
            calendarEventID: calendarEventID,
            plannedSeconds: plannedSeconds
        )
        postFocusRequestNotification()

        let running = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "local.focus")
            .isEmpty

        if !running {
            let appURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Focus.app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: config,
                    completionHandler: nil
                )
            }
        }

        print("focus request queued")
        return true
    } catch {
        fputs("Focus: could not queue calendar focus request: \(error)\n", stderr)
        exit(1)
    }
}

func openAnki() {
    let url = URL(fileURLWithPath: "/Applications/Anki.app")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

// ---- Prompt window: plain mono text, hairline rules, no chrome ----
final class Prompt: NSObject, NSTextFieldDelegate {
    private let askWhy: Bool
    private let window: NSWindow
    private let why = Prompt.field("say why (\(minWhyLength)+ characters)")
    private let improve = Prompt.field("optional")
    private let rating = NSSegmentedControl(labels: ["1", "2", "3", "4", "5"],
                                            trackingMode: .selectOne, target: nil, action: nil)
    private let ok = NSButton(title: "save", target: nil, action: nil)
    private let no = NSButton(title: "", target: nil, action: nil)

    static func field(_ placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.font = mono
        f.placeholderString = placeholder
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        return f
    }

    private func block(_ question: String, _ control: NSView, rule: Bool = true) -> NSView {
        let label = NSTextField(labelWithString: question)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        var views: [NSView] = [label, control]
        if rule {
            let line = NSBox()
            line.boxType = .separator
            views.append(line)
        }
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .width
        s.spacing = 6
        return s
    }

    private init(askWhy: Bool) {
        self.askWhy = askWhy
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()

        why.delegate = self
        rating.selectedSegment = -1
        rating.font = mono
        rating.controlSize = .small
        rating.target = self
        rating.action = #selector(changed)

        no.title = askWhy ? "keep going" : "skip"
        for b in [ok, no] {
            b.isBordered = false
            b.font = mono
            b.target = self
        }
        ok.action = #selector(save)
        ok.keyEquivalent = "\r"
        no.action = #selector(cancel)
        no.keyEquivalent = "\u{1b}"

        let title = NSTextField(labelWithString: askWhy ? "stop?" : "done.")
        title.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.setViews([no], in: .leading)
        buttons.setViews([ok], in: .trailing)

        var rows: [NSView] = [title]
        if askWhy { rows.append(block("why stop", why)) }
        rows.append(block("how productive were you", rating, rule: false))
        rows.append(block("what would make it better", improve))
        rows.append(buttons)

        let root = NSStackView(views: rows)
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 20
        root.edgeInsets = NSEdgeInsets(top: 34, left: 28, bottom: 22, right: 28)
        root.widthAnchor.constraint(equalToConstant: 380).isActive = true

        window.contentView = root
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.level = .floating
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
        update()
    }

    private func update() {
        let whyOK = !askWhy || why.stringValue.trimmed.count >= minWhyLength
        ok.isEnabled = whyOK && rating.selectedSegment >= 0
    }
    func controlTextDidChange(_ n: Notification) { update() }
    @objc private func changed() { update() }
    @objc private func save() { NSApp.stopModal(withCode: .OK) }
    @objc private func cancel() { NSApp.stopModal(withCode: .cancel) }

    /// nil = cancelled ("keep going" / "skip")
    static func run(askWhy: Bool) -> Answer? {
        let p = Prompt(askWhy: askWhy)
        p.window.center()
        NSApp.activate(ignoringOtherApps: true)
        p.window.makeKeyAndOrderFront(nil)
        p.window.makeFirstResponder(askWhy ? p.why : p.improve)
        let code = NSApp.runModal(for: p.window)
        p.window.orderOut(nil)
        guard code == .OK else { return nil }
        return Answer(why: askWhy ? p.why.stringValue.trimmed : nil,
                      rating: p.rating.selectedSegment + 1,
                      improve: p.improve.stringValue.trimmed)
    }
}

// ---- App ----
final class Pomo: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum Phase: String { case idle, focus, shortBreak, longBreak }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let defaults = UserDefaults.standard
    private var phase = Phase.idle
    private var deadline = Date()
    private var cycle = 0
    private var prompting = false
    private var awakeID: IOPMAssertionID = 0
    private var musicPausedAt: Date?
    private var ticker: DispatchSourceTimer?     // one-shot adaptive display/deadline timer
    private var scheduler: DispatchSourceTimer?  // one-shot, fires at next scheduled start
    private var lastRenderKey = ""

    // Cached menu data avoids synchronous disk/network work each time the menu opens.
    private var todayMinutesCached = 0
    private var todaySessionsCached = 0
    private var totalsLoadedForDay = Date.distantPast
    private var cachedAnkiDue: Int?
    private var ankiRefreshInFlight = false
    private var ankiLastRefresh = Date.distantPast

    // Informational state only. Enforcement still lives in deadlock.
    private var deadlockLinked = false
    private var deadlockMessage: String?

    private var configuredFocusMinutes = focusMinutes
    private var configuredShortBreakMinutes = shortBreakMinutes
    private var configuredLongBreakMinutes = longBreakMinutes
    private var configuredLongBreakEvery = longBreakEvery

    private var preferredTimerMode = FocusTimerMode.countdown
    private var activeTimerMode = FocusTimerMode.countdown
    private var focusStartedAt = Date()
    private var countUpProtectionUntil = Date.distantPast

    private var focusDurationSeconds = focusMinutes * 60
    private var focusLabel: String?
    private var focusCalendarEventID: String?
    private var focusPlannedSeconds: Int?

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(externalFocusRequested(_:)),
            name: focusStartNotification,
            object: nil
        )

        let savedFocusMinutes = defaults.integer(forKey: "configuredFocusMinutes")
        let savedShortBreakMinutes = defaults.integer(forKey: "configuredShortBreakMinutes")
        let savedLongBreakMinutes = defaults.integer(forKey: "configuredLongBreakMinutes")
        let savedLongBreakEvery = defaults.integer(forKey: "configuredLongBreakEvery")

        configuredFocusMinutes = savedFocusMinutes > 0
            ? min(720, max(1, savedFocusMinutes))
            : focusMinutes
        configuredShortBreakMinutes = savedShortBreakMinutes > 0
            ? min(120, max(1, savedShortBreakMinutes))
            : shortBreakMinutes
        configuredLongBreakMinutes = savedLongBreakMinutes > 0
            ? min(240, max(1, savedLongBreakMinutes))
            : longBreakMinutes
        configuredLongBreakEvery = savedLongBreakEvery > 0
            ? min(12, max(1, savedLongBreakEvery))
            : longBreakEvery

        preferredTimerMode = FocusTimerMode(
            rawValue: defaults.string(forKey: "preferredTimerMode") ?? ""
        ) ?? .countdown
        activeTimerMode = FocusTimerMode(
            rawValue: defaults.string(forKey: "activeTimerMode") ?? ""
        ) ?? preferredTimerMode

        let savedDuration = defaults.integer(forKey: "focusDurationSeconds")
        focusDurationSeconds = savedDuration > 0
            ? savedDuration
            : configuredFocusMinutes * 60

        focusLabel = defaults.string(forKey: "focusLabel")
        focusCalendarEventID = defaults.string(forKey: "focusCalendarEventID")

        let savedPlanned = defaults.integer(forKey: "focusPlannedSeconds")
        focusPlannedSeconds = savedPlanned > 0 ? savedPlanned : nil

        focusStartedAt =
            (defaults.object(forKey: "focusStartedAt") as? Date) ?? Date()
        countUpProtectionUntil =
            (defaults.object(forKey: "countUpProtectionUntil") as? Date)
            ?? .distantPast

        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu

        if !defaults.bool(forKey: "didInit") {
            try? SMAppService.mainApp.register()   // open at login by default
            defaults.set(true, forKey: "didInit")
        }

        loadTodayTotals()
        refreshAnkiDueIfNeeded(force: true)
        pingDeadlock { [weak self] ok in
            self?.deadlockLinked = ok
        }

        // Relaunching mid-session resumes it: quitting is not an escape.
        cycle = defaults.integer(forKey: "cycle")
        if let raw = defaults.string(forKey: "phase"),
           let p = Phase(rawValue: raw),
           p != .idle {
            let now = Date()
            let savedDeadline = defaults.object(forKey: "deadline") as? Date

            if p == .focus,
               activeTimerMode == .countUp,
               focusStartedAt <= now,
               now.timeIntervalSince(focusStartedAt) < 12 * 60 * 60 {
                phase = p
                deadline = savedDeadline
                    ?? focusStartedAt.addingTimeInterval(
                        Double(max(60, focusDurationSeconds))
                    )
                startTicker()
                setAwake(keepAwakeDuringFocus)
                ensureCountUpDeadlockProtection(force: true)
            } else if let dl = savedDeadline, dl > now {
                phase = p
                deadline = dl
                startTicker()

                if p == .focus {
                    setAwake(keepAwakeDuringFocus)

                    let remaining = Int(
                        ceil(dl.timeIntervalSinceNow)
                    )
                    if remaining >= 15 * 60 {
                        syncDeadlockForFocus(seconds: remaining)
                    }
                }
            } else {
                defaults.set("idle", forKey: "phase")
                phase = .idle
            }
        }
        render()
        armSchedule()

        DispatchQueue.main.async { [weak self] in
            self?.consumeExternalFocusRequest()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tick()
            self?.armSchedule()
        }
    }

    // MARK: timer logic (deadline-based, so sleep can't skew it)

    private func phaseDurationSeconds(_ p: Phase) -> Int {
        switch p {
        case .focus: return focusDurationSeconds
        case .shortBreak: return configuredShortBreakMinutes * 60
        case .longBreak: return configuredLongBreakMinutes * 60
        case .idle: return 0
        }
    }

    private func begin(
        _ p: Phase,
        customFocusSeconds: Int? = nil,
        label: String? = nil,
        calendarEventID: String? = nil,
        plannedSeconds: Int? = nil
    ) {
        if p == .focus {
            focusDurationSeconds = max(
                60,
                min(
                    customFocusSeconds ?? (configuredFocusMinutes * 60),
                    12 * 60 * 60
                )
            )
            activeTimerMode = preferredTimerMode
            focusStartedAt = Date()
            countUpProtectionUntil = .distantPast

            defaults.set(activeTimerMode.rawValue, forKey: "activeTimerMode")
            defaults.set(focusStartedAt, forKey: "focusStartedAt")

            focusLabel = label?.trimmed
            if focusLabel?.isEmpty == true { focusLabel = nil }

            defaults.set(focusDurationSeconds, forKey: "focusDurationSeconds")
            if let focusLabel {
                defaults.set(focusLabel, forKey: "focusLabel")
            } else {
                defaults.removeObject(forKey: "focusLabel")
            }

            let cleanEventID = calendarEventID?.trimmed
            focusCalendarEventID = (cleanEventID?.isEmpty == false)
                ? cleanEventID
                : nil
            focusPlannedSeconds = plannedSeconds.map {
                max(60, min($0, 12 * 60 * 60))
            }

            if let focusCalendarEventID {
                defaults.set(
                    focusCalendarEventID,
                    forKey: "focusCalendarEventID"
                )
            } else {
                defaults.removeObject(forKey: "focusCalendarEventID")
            }

            if let focusPlannedSeconds {
                defaults.set(
                    focusPlannedSeconds,
                    forKey: "focusPlannedSeconds"
                )
            } else {
                defaults.removeObject(forKey: "focusPlannedSeconds")
            }
        }

        phase = p

        if p == .focus, activeTimerMode == .countUp {
            // In count-up mode this is a target/planned boundary, not an auto-stop.
            deadline = focusStartedAt.addingTimeInterval(
                Double(max(60, focusDurationSeconds))
            )
        } else {
            deadline = Date().addingTimeInterval(
                Double(phaseDurationSeconds(p))
            )
        }

        defaults.set(p.rawValue, forKey: "phase")
        defaults.set(deadline, forKey: "deadline")
        startTicker()

        if p == .focus {
            setAwake(keepAwakeDuringFocus)
            runShortcut(focusOnShortcut)
            resumeMusic()

            if activeTimerMode == .countUp {
                ensureCountUpDeadlockProtection(force: true)
            } else {
                syncDeadlockForFocus(seconds: focusDurationSeconds)
            }
        } else {
            setAwake(false)
            runShortcut(focusOffShortcut)
        }
        render()
        postFocusStateNotification()
    }

    @objc private func externalFocusRequested(_ note: Notification) {
        consumeExternalFocusRequest()
    }

    private func consumeExternalFocusRequest() {
        guard FileManager.default.fileExists(atPath: focusRequestURL.path) else { return }

        defer { try? FileManager.default.removeItem(at: focusRequestURL) }

        guard let data = try? Data(contentsOf: focusRequestURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let request = try? decoder.decode(ExternalFocusRequest.self, from: data) else {
            return
        }

        guard abs(request.createdAt.timeIntervalSinceNow) < 10 * 60 else { return }

        if phase == .focus {
            NSSound.beep()
            return
        }
        if phase != .idle {
            stop()
        }

        begin(
            .focus,
            customFocusSeconds: request.seconds,
            label: request.title,
            calendarEventID: request.calendarEventID,
            plannedSeconds: request.plannedSeconds ?? request.seconds
        )
    }

    private func stop() {
        let was = phase
        phase = .idle
        ticker?.cancel()
        ticker = nil
        defaults.set("idle", forKey: "phase")
        defaults.removeObject(forKey: "activeTimerMode")
        defaults.removeObject(forKey: "focusStartedAt")
        defaults.removeObject(forKey: "countUpProtectionUntil")
        countUpProtectionUntil = .distantPast
        setAwake(false)
        if was == .focus { runShortcut(focusOffShortcut) }
        render()
        postFocusStateNotification()
    }

    private func ensureCountUpDeadlockProtection(force: Bool = false) {
        guard phase == .focus,
              activeTimerMode == .countUp,
              deadlockBlocksDuringFocus else {
            return
        }

        let now = Date()

        if !force,
           countUpProtectionUntil.timeIntervalSince(now) > 2 * 60 {
            return
        }

        let seconds: Int
        if force {
            seconds = max(
                15 * 60,
                focusPlannedSeconds ?? focusDurationSeconds
            )
        } else {
            // Keep open-ended sessions protected in small chunks so a manual
            // finish cannot leave a huge unnecessary block behind.
            seconds = 15 * 60
        }

        countUpProtectionUntil = now.addingTimeInterval(
            Double(seconds)
        )
        defaults.set(
            countUpProtectionUntil,
            forKey: "countUpProtectionUntil"
        )

        syncDeadlockForFocus(seconds: seconds)
    }

    private func syncDeadlockForFocus(seconds: Int) {
        guard deadlockBlocksDuringFocus else {
            deadlockLinked = false
            deadlockMessage = nil
            return
        }

        startDeadlockDistractionBlock(seconds: seconds) { [weak self] ok, message in
            self?.deadlockLinked = ok
            self?.deadlockMessage = ok ? nil : message
        }
    }

    /// Holds a power assertion so the display (and Mac) stay awake; released on break/stop/quit.
    private func setAwake(_ on: Bool) {
        if on, awakeID == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Focus session" as CFString, &awakeID)
        } else if !on, awakeID != 0 {
            IOPMAssertionRelease(awakeID)
            awakeID = 0
        }
    }

    /// Only resumes music this app paused, and only if that was recent.
    private func resumeMusic() {
        guard musicPausesOnBreak, let t = musicPausedAt else { return }
        musicPausedAt = nil
        if Date().timeIntervalSince(t) < 30 * 60 { sendPlayPause() }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = nil
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        guard phase != .idle, !prompting else { return }

        if phase == .focus, activeTimerMode == .countUp {
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(
                deadline: .now() + 1,
                leeway: .milliseconds(180)
            )
            t.setEventHandler { [weak self] in
                self?.tick()
            }
            t.resume()

            ticker?.cancel()
            ticker = t
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            finish()
            return
        }

        // Keep the displayed countdown moving once per second for the entire
        // focus/break session. The wall-clock deadline remains authoritative,
        // so delayed ticks or app wake-ups cannot accumulate timer drift.
        let delay = min(remaining, 1)

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(
            deadline: .now() + delay,
            leeway: .milliseconds(80)
        )

        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()

        ticker?.cancel()
        ticker = t
    }

    private func tick() {
        guard phase != .idle, !prompting else { return }

        if phase == .focus, activeTimerMode == .countUp {
            ensureCountUpDeadlockProtection()
            render()
            scheduleNextTick()
            return
        }

        if deadline.timeIntervalSinceNow <= 0 {
            finish()
        } else {
            render()
            scheduleNextTick()
        }
    }

    private func finish() {
        // Check before our own chime plays, or the chime would look like music.
        if phase == .focus, musicPausesOnBreak, audioIsPlaying() {
            sendPlayPause()
            musicPausedAt = Date()
        }
        NSSound(named: "Glass")?.play()
        guard phase == .focus else { stop(); return }
        cycle += 1
        defaults.set(cycle, forKey: "cycle")
        begin(cycle % configuredLongBreakEvery == 0 ? .longBreak : .shortBreak)
        DispatchQueue.main.async { [self] in
            prompting = true
            defer { prompting = false }
            let a = Prompt.run(askWhy: false) ?? Answer(why: nil, rating: nil, improve: "")
            record(
                "completed",
                max(1, Int((Double(focusDurationSeconds) / 60.0).rounded())),
                a
            )
            if ankiOnBreak { openAnki() }
        }
    }

    @objc private func finishCountUpTapped() {
        guard phase == .focus,
              activeTimerMode == .countUp else {
            return
        }

        if musicPausesOnBreak, audioIsPlaying() {
            sendPlayPause()
            musicPausedAt = Date()
        }

        let done = max(1, elapsedMinutes())

        prompting = true
        let answer = Prompt.run(askWhy: false)
            ?? Answer(why: nil, rating: nil, improve: "")
        prompting = false

        record("completed", done, answer)

        cycle += 1
        defaults.set(cycle, forKey: "cycle")

        begin(
            cycle % configuredLongBreakEvery == 0
            ? .longBreak
            : .shortBreak
        )

        if ankiOnBreak {
            openAnki()
        }
    }

    /// Stop / Quit. During focus this demands a written reason first.
    private func requestEnd(quit: Bool) {
        if phase == .focus {
            let done = elapsedMinutes()
            prompting = true
            defer { prompting = false }
            guard let a = Prompt.run(askWhy: true) else { return }   // kept going
            record("stopped", done, a)
        }
        if phase != .idle { stop() }
        if quit { NSApp.terminate(nil) }
    }

    private func record(_ kind: String, _ minutes: Int, _ a: Answer) {
        let e = Entry(
            date: Date(),
            kind: kind,
            minutes: minutes,
            why: a.why,
            rating: a.rating,
            improve: a.improve.isEmpty ? nil : a.improve,
            label: focusLabel,
            calendarEventID: focusCalendarEventID,
            plannedMinutes: focusPlannedSeconds.map {
                max(1, Int((Double($0) / 60.0).rounded()))
            }
        )
        appendLog(e)
        appendNote(e)
        ensureTodayTotalsCurrent()
        todayMinutesCached += e.minutes
        todaySessionsCached += 1
    }

    // MARK: menubar display — a pill that fills as you focus and drains as you rest.
    // Drawn as a template image (system tints it), time knocked out of the fill.

    private func pill(_ text: String, fill: CGFloat) -> NSImage {
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let ts = str.size()
        let size = NSSize(width: ceil(ts.width) + 16, height: 17)
        let img = NSImage(size: size, flipped: false) { rect in
            let r = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
            let filled = NSRect(x: 0, y: 0, width: rect.width * fill, height: rect.height)
            let at = NSPoint(x: (rect.width - ts.width) / 2, y: (rect.height - ts.height) / 2)

            if fill > 0 {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                NSColor.black.setFill()
                filled.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            NSColor.black.setStroke()
            path.lineWidth = 1
            path.stroke()

            str.draw(at: at)
            if fill > 0 {
                NSGraphicsContext.saveGraphicsState()
                filled.clip()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                str.draw(at: at)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    private func render() {
        let text: String
        var fill: CGFloat = 0

        if phase == .idle {
            if preferredTimerMode == .countUp {
                text = "↑00:00"
            } else {
                text = String(
                    format: "%02d:00",
                    configuredFocusMinutes
                )
            }
        } else if phase == .focus,
                  activeTimerMode == .countUp {
            let elapsedSeconds = max(
                0,
                Int(
                    Date()
                        .timeIntervalSince(focusStartedAt)
                        .rounded(.down)
                )
            )
            text = String(
                format: "↑%02d:%02d",
                elapsedSeconds / 60,
                elapsedSeconds % 60
            )

            let target = max(1, focusDurationSeconds)
            fill = min(
                1,
                CGFloat(elapsedSeconds) / CGFloat(target)
            )
        } else {
            let left = max(0, deadline.timeIntervalSinceNow)
            let seconds = Int(left.rounded(.up))
            text = String(
                format: "%02d:%02d",
                seconds / 60,
                seconds % 60
            )

            let duration = max(1, phaseDurationSeconds(phase))
            let elapsed = CGFloat(
                1 - left / Double(duration)
            )
            fill = phase == .focus
                ? elapsed
                : 1 - elapsed
        }

        let clamped = max(0, min(1, fill))
        let key = "\(text)|\(Int((clamped * 1000).rounded()))"
        guard key != lastRenderKey else { return }
        lastRenderKey = key
        item.button?.image = pill(text, fill: clamped)
    }

    // MARK: today's totals

    private func elapsedMinutes() -> Int {
        if phase == .focus,
           activeTimerMode == .countUp {
            return max(
                0,
                Int(
                    Date()
                        .timeIntervalSince(focusStartedAt)
                        / 60
                )
            )
        }

        let total = Double(focusDurationSeconds)
        return max(
            0,
            Int(
                (
                    total -
                    max(0, deadline.timeIntervalSinceNow)
                ) / 60
            )
        )
    }

    private func loadTodayTotals() {
        todayMinutesCached = 0
        todaySessionsCached = 0
        totalsLoadedForDay = Date()

        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 512 * 1024
        let offset = end > maxBytes ? end - maxBytes : 0

        if offset > 0 {
            try? handle.seek(toOffset: offset)
        } else {
            try? handle.seek(toOffset: 0)
        }

        var data = handle.readDataToEndOfFile()
        if offset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...firstNewline)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in data.split(separator: 0x0A) {
            if let entry = try? decoder.decode(Entry.self, from: Data(line)),
               Calendar.current.isDateInToday(entry.date) {
                todayMinutesCached += entry.minutes
                todaySessionsCached += 1
            }
        }
    }

    private func ensureTodayTotalsCurrent() {
        guard !Calendar.current.isDateInToday(totalsLoadedForDay) else { return }
        loadTodayTotals()
    }

    private func todayLine() -> String {
        ensureTodayTotalsCurrent()

        var minutes = todayMinutesCached
        var sessions = todaySessionsCached

        if phase == .focus {
            minutes += elapsedMinutes()
            sessions += 1
        }

        let time = minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(minutes)m"

        return "today  \(time) · \(sessions) session\(sessions == 1 ? "" : "s")"
    }

    private func refreshAnkiDueIfNeeded(force: Bool = false) {
        guard ankiOnBreak, !ankiRefreshInFlight else { return }
        guard force || Date().timeIntervalSince(ankiLastRefresh) > 60 else { return }

        ankiRefreshInFlight = true
        fetchAnkiDue { [weak self] count in
            guard let self else { return }
            self.ankiRefreshInFlight = false
            self.ankiLastRefresh = Date()
            self.cachedAnkiDue = count
        }
    }

    // MARK: schedule (a single wall-clock one-shot; zero cost between fires)

    private func armSchedule() {
        scheduler?.cancel()
        scheduler = nil
        let cal = Calendar.current
        let next = schedule.compactMap { s -> Date? in
            let comps = DateComponents(hour: s.hour, minute: s.minute, second: 0)
            var d = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
            while let x = d, cal.isDateInWeekend(x) {
                d = cal.nextDate(after: x, matching: comps, matchingPolicy: .nextTime)
            }
            return d
        }.min()
        guard let fire = next else { return }

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(wallDeadline: .now() + fire.timeIntervalSinceNow, leeway: .seconds(1))
        t.setEventHandler { [weak self] in
            if self?.phase == .idle { self?.begin(.focus) }
            self?.armSchedule()
        }
        t.resume()
        scheduler = t
    }

    @objc private func editTimerSettings() {
        let current = TimerSettings(
            focusMinutes: configuredFocusMinutes,
            shortBreakMinutes: configuredShortBreakMinutes,
            longBreakMinutes: configuredLongBreakMinutes,
            longBreakEvery: configuredLongBreakEvery,
            mode: preferredTimerMode
        )

        guard let updated = TimerSettingsPrompt.run(
            current: current
        ) else {
            return
        }

        configuredFocusMinutes = updated.focusMinutes
        configuredShortBreakMinutes = updated.shortBreakMinutes
        configuredLongBreakMinutes = updated.longBreakMinutes
        configuredLongBreakEvery = updated.longBreakEvery
        preferredTimerMode = updated.mode

        defaults.set(
            configuredFocusMinutes,
            forKey: "configuredFocusMinutes"
        )
        defaults.set(
            configuredShortBreakMinutes,
            forKey: "configuredShortBreakMinutes"
        )
        defaults.set(
            configuredLongBreakMinutes,
            forKey: "configuredLongBreakMinutes"
        )
        defaults.set(
            configuredLongBreakEvery,
            forKey: "configuredLongBreakEvery"
        )
        defaults.set(
            preferredTimerMode.rawValue,
            forKey: "preferredTimerMode"
        )

        if phase == .idle {
            focusDurationSeconds = configuredFocusMinutes * 60
            activeTimerMode = preferredTimerMode
        }

        lastRenderKey = ""
        render()
    }

    // MARK: menu (built only when opened)

    @discardableResult
    private func add(_ m: NSMenu, _ title: String, _ sel: Selector?, key: String = "",
                     on: Bool = false, dim: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: mono,
            .foregroundColor: dim ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        i.target = self
        i.state = on ? .on : .off
        i.isEnabled = sel != nil
        m.addItem(i)
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, lines[cycle % lines.count], nil, dim: true)
        add(menu, todayLine(), nil, dim: true)

        refreshAnkiDueIfNeeded()
        if ankiOnBreak, let due = cachedAnkiDue {
            add(menu, "anki  \(due) due", nil, dim: true)
        }

        if deadlockBlocksDuringFocus {
            let label = deadlockLinked ? "deadlock  linked" : "deadlock  unavailable"
            add(menu, label, nil, dim: true)
        }

        if phase == .focus, let focusLabel, !focusLabel.isEmpty {
            add(menu, "block  \(focusLabel)", nil, dim: true)
        }

        let timerSummary =
            "timer  \(preferredTimerMode.menuLabel) · " +
            "\(configuredFocusMinutes)m / " +
            "\(configuredShortBreakMinutes)m / " +
            "\(configuredLongBreakMinutes)m"
        add(menu, timerSummary, nil, dim: true)

        menu.addItem(.separator())

        if phase == .idle {
            add(menu, "start", #selector(startFocus))
        } else if phase == .focus,
                  activeTimerMode == .countUp {
            add(
                menu,
                "finish…",
                #selector(finishCountUpTapped)
            )
        } else {
            add(
                menu,
                phase == .focus ? "stop…" : "stop",
                #selector(stopTapped)
            )
        }

        add(
            menu,
            "timer settings…",
            #selector(editTimerSettings)
        )
        add(menu, "log", #selector(openLog))
        add(menu, "log note…", #selector(chooseNote))
        add(menu, "login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add(menu, phase == .focus ? "quit…" : "quit", #selector(quit), key: "q")
    }

    @objc private func startFocus() { begin(.focus) }
    @objc private func stopTapped() { requestEnd(quit: false) }
    @objc private func quit() { requestEnd(quit: true) }
    /// Opens the chosen Obsidian note if there is one, otherwise reveals the raw JSONL log.
    @objc private func openLog() {
        if let path = defaults.string(forKey: "note"), FileManager.default.fileExists(atPath: path) {
            var c = URLComponents(string: "obsidian://open")!
            c.queryItems = [URLQueryItem(name: "path", value: path)]
            if let u = c.url { NSWorkspace.shared.open(u); return }
        }
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            let dir = logURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }
    /// Pick the existing note sessions get appended to (create it in Obsidian first).
    @objc private func chooseNote() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.message = "Choose the Obsidian note to append sessions to"
        p.allowedContentTypes = [UTType(filenameExtension: "md")].compactMap { $0 }
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let u = p.url { defaults.set(u.path, forKey: "note") }
    }
    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch { NSSound.beep() }
    }
}

if runFocusRequestHelperIfNeeded() {
    exit(0)
}

let app = NSApplication.shared
let delegate = Pomo()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
