import Observation
import AppKit

enum TimerState { case idle, running, paused }

// ── Distraction event (logged during a session) ───────────────────────────────

struct DistractionEvent: Codable, Identifiable {
    var id        = UUID()
    var timestamp : Date
    var label     : String   // "Phone", "Social", "Other", etc.
    var offsetSec : Int      // seconds into the session when it happened
}

// ── Pause interval (for session replay) ──────────────────────────────────────

struct PauseInterval: Codable {
    var start : Date
    var end   : Date?
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

// ── Timer ─────────────────────────────────────────────────────────────────────

@Observable
final class StudyTimer {
    static let shared = StudyTimer()

    var elapsed        : TimeInterval = 0
    var state          : TimerState   = .idle
    var distractions   : [DistractionEvent] = []
    var currentSubject : String       = ""   // set by SessionEndView / notch start flow
    var targetDuration : TimeInterval? = nil  // Pomodoro target (nil = free mode)
    var sessionNotes   : String       = ""   // quick notes during session

    private(set) var sessionStart : Date?
    private var timerStartDate    : Date?
    private var accumulated       : TimeInterval = 0
    private var ticker            : Timer?

    // Replay data
    private(set) var pauseIntervals: [PauseInterval] = []

    // Break reminder: fire once if unbroken run > 90 min
    private var breakReminderFired = false

    // App usage tracking (bundleID -> total seconds)
    private(set) var appUsage: [String: TimeInterval] = [:]
    private var lastAppPoll: Date?
    private var appPollTicker: Timer?

    // ── Controls ──────────────────────────────────────────────────────────────

    func start() {
        guard state != .running else { return }
        if sessionStart == nil {
            sessionStart = Date()
            SoundService.shared.resetMilestones()
            SoundService.shared.playSessionStart()
        }
        // Close open pause interval
        if var last = pauseIntervals.last, last.end == nil {
            last.end = Date()
            pauseIntervals[pauseIntervals.count - 1] = last
        }
        timerStartDate = Date()
        state = .running
        HapticService.shared.playTimerStart()
        startAppPolling()

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let t = self.timerStartDate else { return }
            self.elapsed = self.accumulated + Date().timeIntervalSince(t)
            SoundService.shared.checkMilestones(elapsed: self.elapsed)
            self.checkBreakReminder()
            self.checkExamWarning()
            // Pomodoro auto-finish
            if let target = self.targetDuration, self.elapsed >= target {
                let subject = self.currentSubject  // capture before finish() clears it
                DispatchQueue.main.async {
                    if let data = self.finish() {
                        SessionEndWindowController.present(sessionData: data, preselectedSubject: subject)
                    }
                }
            }
        }
    }

    func pause() {
        guard state == .running else { return }
        if let t = timerStartDate { accumulated += Date().timeIntervalSince(t) }
        ticker?.invalidate(); ticker = nil; timerStartDate = nil
        stopAppPolling()
        pauseIntervals.append(PauseInterval(start: Date()))
        state = .paused
        HapticService.shared.playTimerPause()
    }

    func finish() -> (start: Date, end: Date, duration: TimeInterval,
                      distractions: [DistractionEvent], pauses: [PauseInterval],
                      appUsage: [String: TimeInterval])? {
        guard elapsed > 0 else { reset(); return nil }
        if state == .running {
            if let t = timerStartDate { accumulated += Date().timeIntervalSince(t) }
            ticker?.invalidate(); ticker = nil
        }
        // Close open pause
        if var last = pauseIntervals.last, last.end == nil {
            last.end = Date()
            pauseIntervals[pauseIntervals.count - 1] = last
        }
        let end      = Date()
        let start    = sessionStart ?? end.addingTimeInterval(-accumulated)
        let duration = accumulated
        let dists    = distractions
        let pauses   = pauseIntervals
        let apps     = appUsage
        SoundService.shared.playSessionEnd()
        HapticService.shared.playTimerComplete()
        reset()
        return (start, end, duration, dists, pauses, apps)
    }

    private func startAppPolling() {
        lastAppPoll = Date()
        appPollTicker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollAppUsage()
        }
    }

    private func stopAppPolling() {
        pollAppUsage() // one last poll to capture the tail
        appPollTicker?.invalidate()
        appPollTicker = nil
        lastAppPoll = nil
    }

    private func pollAppUsage() {
        guard let last = lastAppPoll else { return }
        let now = Date()
        let diff = now.timeIntervalSince(last)
        lastAppPoll = now
        
        if let app = NSWorkspace.shared.frontmostApplication, let bid = app.bundleIdentifier {
            appUsage[bid, default: 0] += diff
        }
    }

    func reset() {
        ticker?.invalidate(); ticker = nil
        stopAppPolling()
        timerStartDate = nil; sessionStart = nil
        accumulated = 0; elapsed = 0; state = .idle
        distractions = []; pauseIntervals = []
        appUsage = [:]
        breakReminderFired = false
        targetDuration = nil
        sessionNotes = ""
        currentSubject = ""
    }

    /// Start a Pomodoro session with a target duration in minutes
    func startWithTarget(_ minutes: Int) {
        targetDuration = TimeInterval(minutes * 60)
        start()
    }

    func toggle() {
        switch state {
        case .idle, .paused: start()
        case .running:       pause()
        }
    }

    // ── Distraction logging ───────────────────────────────────────────────────

    func logDistraction(label: String) {
        let event = DistractionEvent(
            timestamp: Date(),
            label    : label,
            offsetSec: Int(elapsed)
        )
        distractions.append(event)
        HapticService.shared.playDistraction()
        SoundService.shared.playDistraction()
    }

    // ── Alerts ────────────────────────────────────────────────────────────────

    private func checkBreakReminder() {
        guard !breakReminderFired, elapsed > 90 * 60 else { return }
        breakReminderFired = true
        SoundService.shared.playBreakReminder()
    }

    private func checkExamWarning() {
        guard let sub = ModeStore.shared.activeCollegeSubject,
              let hours = sub.hoursUntilExam,
              hours > 0, hours <= 24 else { return }
        // Fire once per session (use a simple flag via UserDefaults)
        let key = "examWarnFired_\(sub.id)"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if UserDefaults.standard.double(forKey: key) != today {
            UserDefaults.standard.set(today, forKey: key)
            SoundService.shared.playExamWarning()
        }
    }

    // ── Formatting ────────────────────────────────────────────────────────────

    var formattedTime: String {
        let h = Int(elapsed)/3600; let m = (Int(elapsed)%3600)/60; let s = Int(elapsed)%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    var shortTime: String {
        let h = Int(elapsed)/3600; let m = (Int(elapsed)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
