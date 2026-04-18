import AppKit
import AVFoundation
import UserNotifications

// ── Sound Service ─────────────────────────────────────────────────────────────
// Uses NSSound system sounds — no audio files needed, works out of the box.

enum SoundTheme: String, Codable, CaseIterable {
    case classic = "Classic"
    case modern  = "Modern"
    case zen     = "Zen"
    case muted   = "Muted"
    
    var startsound: String {
        switch self {
        case .classic: return "Blow"
        case .modern:  return "Frog"
        case .zen:     return "Purr"
        case .muted:   return ""
        }
    }
    
    var endsound: String {
        switch self {
        case .classic: return "Hero"
        case .modern:  return "Glass"
        case .zen:     return "Submarine"
        case .muted:   return ""
        }
    }
    
    var milestone: String {
        switch self {
        case .classic: return "Tink"
        case .modern:  return "Morse"
        case .zen:     return "Ping"
        case .muted:   return ""
        }
    }
}

final class SoundService {
    static let shared = SoundService()

    // User can toggle sounds in UserDefaults
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    var theme: SoundTheme {
        get {
            guard let str = UserDefaults.standard.string(forKey: "soundTheme"),
                  let t = SoundTheme(rawValue: str) else { return .classic }
            return t
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "soundTheme") }
    }

    private var lastMilestone: Int = 0   // track which 30-min block we already fired

    // Call every second from StudyTimer
    func checkMilestones(elapsed: TimeInterval) {
        guard enabled, theme != .muted else { return }
        let minutes = Int(elapsed / 60)
        let block   = minutes / 30          // 0=0-29, 1=30-59, 2=60-89 …
        guard block > 0, block != lastMilestone else { return }
        lastMilestone = block
        if minutes % 60 == 0 {
            play(theme.endsound)                   // on the hour: Theme end chime
            showBanner("⏰ \(minutes / 60)h milestone!", body: "Keep going!")
        } else {
            play(theme.milestone)                    // every 30 min: theme milestone
        }
    }

    func playDistraction() {
        guard enabled, theme != .muted else { return }
        play("Basso")
    }

    func playSessionStart() {
        guard enabled, theme != .muted else { return }
        play(theme.startsound)
    }

    func playSessionEnd() {
        guard enabled, theme != .muted else { return }
        play(theme.endsound)
    }

    func playExamWarning() {
        guard enabled, theme != .muted else { return }
        play("Sosumi")
        showBanner("📅 Exam Soon!", body: "Less than 24 hours to go.")
    }

    func playBreakReminder() {
        guard enabled, theme != .muted else { return }
        play("Ping")
        showBanner("🧠 Take a break", body: "You've been studying for over 90 minutes.")
    }

    func resetMilestones() { lastMilestone = 0 }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func play(_ name: String) {
        DispatchQueue.main.async {
            NSSound(named: NSSound.Name(name))?.play()
        }
    }

    private func showBanner(_ title: String, body: String) {
        // UNUserNotificationCenter requires a bundle — skip silently if not available
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = nil
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}

