import Foundation
import UserNotifications
import AppKit

// ── Spaced Repetition Service ─────────────────────────────────────────────────
//
//  Uses a simplified SM-2 algorithm to decide when to remind the user to review
//  a subject, based on:
//    - Days since last studied
//    - Average difficulty (1=Hard → shorter interval; 5=Easy → longer interval)
//    - Number of sessions (more sessions = longer safe interval)
//
//  Intervals (days):
//    Hard (avg diff 1–2)  →  1, 2, 4, 7, 14
//    Medium (avg diff 3)  →  1, 3, 7, 14, 30
//    Easy (avg diff 4–5)  →  2, 5, 10, 21, 60
//
//  Called on app launch and once per day (via AppDelegate timer).

final class SpacedRepetitionService {
    static let shared = SpacedRepetitionService()

    // ── Check all subjects and schedule reminders for overdue ones ────────────

    func checkAndSchedule() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            self.processSubjects()
        }
    }

    private func processSubjects() {
        let store    = SessionStore.shared
        let subjects = store.knownSubjects

        // Remove all existing spaced repetition notifications first
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: subjects.map { "sr_" + $0 }
            )
        }

        for subject in subjects {
            let sessions = store.sessions.filter { $0.subject == subject }
            guard !sessions.isEmpty else { continue }

            // Days since last studied
            guard let lastDate = sessions.map({ $0.startTime }).max() else { continue }
            let daysSince = Date().timeIntervalSince(lastDate) / 86400

            // Average difficulty (1=Hard 5=Easy)
            let rated     = sessions.filter { $0.difficulty > 0 }
            let avgDiff   = rated.isEmpty ? 3.0
                : Double(rated.map { $0.difficulty }.reduce(0, +)) / Double(rated.count)

            // Repetition count (number of sessions)
            let reps = sessions.count

            // Calculate recommended interval
            let interval = recommendedInterval(avgDiff: avgDiff, reps: reps)

            // If overdue, schedule a notification for "now + small delay"
            if daysSince >= Double(interval) {
                scheduleReminder(subject: subject, daysSince: Int(daysSince),
                                 avgDiff: avgDiff, interval: interval)
            }
        }
    }

    private func recommendedInterval(avgDiff: Double, reps: Int) -> Int {
        // SM-2 inspired intervals based on difficulty
        let easyIntervals  : [Int] = [2, 5, 10, 21, 60]
        let medIntervals   : [Int] = [1, 3,  7, 14, 30]
        let hardIntervals  : [Int] = [1, 2,  4,  7, 14]

        let intervals: [Int]
        if avgDiff >= 4.0      { intervals = easyIntervals }
        else if avgDiff >= 2.5 { intervals = medIntervals }
        else                   { intervals = hardIntervals }

        let idx = min(reps - 1, intervals.count - 1)
        return intervals[max(0, idx)]
    }

    private func scheduleReminder(subject: String, daysSince: Int, avgDiff: Double, interval: Int) {
        let content        = UNMutableNotificationContent()
        let diffLabel      = avgDiff <= 2 ? "⭐ Hard" : avgDiff <= 3.5 ? "⭐⭐⭐ Medium" : "⭐⭐⭐⭐⭐ Easy"
        content.title      = "📚 Time to review \(subject)"
        content.body       = "You haven't studied \(subject) in \(daysSince) day\(daysSince == 1 ? "" : "s"). Rated \(diffLabel) — recommended every \(interval) days."
        content.sound      = .default
        content.userInfo   = ["subject": subject]
        content.categoryIdentifier = "SPACED_REPETITION"

        // Schedule for 10am today (or immediately if already past 10am)
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10; comps.minute = 0
        var fireDate = Calendar.current.date(from: comps) ?? Date()
        if fireDate < Date() { fireDate = Date().addingTimeInterval(60) } // fire in 1 min if past 10am

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: "sr_" + subject, content: content, trigger: trigger)
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().add(request) { err in
            if let e = err { print("[SR] notification error: \(e)") }
        }
    }

    // ── Subject review status (for UI display) ────────────────────────────────

    struct SubjectStatus {
        let subject      : String
        let daysSince    : Int
        let interval     : Int
        let isOverdue    : Bool
        let daysOverdue  : Int
        let avgDiff      : Double
        let urgency      : Urgency

        enum Urgency { case ok, soon, overdue, critical }
    }

    func statusForAllSubjects() -> [SubjectStatus] {
        let store    = SessionStore.shared
        return store.knownSubjects.compactMap { subject in
            let sessions = store.sessions.filter { $0.subject == subject }
            guard let lastDate = sessions.map({ $0.startTime }).max() else { return nil }
            let daysSince = Int(Date().timeIntervalSince(lastDate) / 86400)
            let rated     = sessions.filter { $0.difficulty > 0 }
            let avgDiff   = rated.isEmpty ? 3.0
                : Double(rated.map { $0.difficulty }.reduce(0, +)) / Double(rated.count)
            let interval  = recommendedInterval(avgDiff: avgDiff, reps: sessions.count)
            let isOverdue = daysSince >= interval
            let overdueDays = max(0, daysSince - interval)

            let urgency: SubjectStatus.Urgency
            if !isOverdue               { urgency = daysSince >= interval - 1 ? .soon : .ok }
            else if overdueDays <= 2    { urgency = .overdue }
            else                        { urgency = .critical }

            return SubjectStatus(subject: subject, daysSince: daysSince,
                                 interval: interval, isOverdue: isOverdue,
                                 daysOverdue: overdueDays, avgDiff: avgDiff, urgency: urgency)
        }
        .sorted { a, b in
            // Sort: critical first, then overdue, then by days overdue descending
            if a.urgency == b.urgency { return a.daysOverdue > b.daysOverdue }
            let order: [SubjectStatus.Urgency] = [.critical, .overdue, .soon, .ok]
            return (order.firstIndex(of: a.urgency) ?? 4) < (order.firstIndex(of: b.urgency) ?? 4)
        }
    }
}
