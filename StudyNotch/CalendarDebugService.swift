import Foundation
import Observation
import EventKit
import SwiftUI
import Observation

// ── Calendar Debug Service ────────────────────────────────────────────────────
//
//  Provides:
//    1. iCloud/system calendar integration via EventKit
//    2. Debug log ring-buffer shown in UI
//    3. Unified error reporting for both Google Calendar and EventKit
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class CalendarDebugService {
    static let shared = CalendarDebugService()

    // ── Debug log ─────────────────────────────────────────────────────────────
     var logs: [LogEntry] = []

    struct LogEntry: Identifiable {
        var id        = UUID()
        var timestamp = Date()
        var level     : LogLevel
        var source    : String   // "iCloud" | "Google" | "System"
        var message   : String

        enum LogLevel: String { case info = "ℹ️"; case ok = "✅"; case warn = "⚠️"; case error = "❌" }

        var formatted: String {
            let tf = DateFormatter(); tf.timeStyle = .medium
            return "[\(tf.string(from: timestamp))] \(level.rawValue) [\(source)] \(message)"
        }
    }

    func log(_ level: LogEntry.LogLevel, source: String, _ message: String) {
        DispatchQueue.main.async {
            self.logs.insert(LogEntry(level: level, source: source, message: message), at: 0)
            if self.logs.count > 100 { self.logs = Array(self.logs.prefix(100)) }
        }
        print("[CalDebug] \(level.rawValue) [\(source)] \(message)")
    }

    func clearLogs() { logs = [] }

    // ── EventKit (iCloud / system calendars) ─────────────────────────────────

    private let eventStore = EKEventStore()
     var iCloudAuthorized: Bool   = false
     var iCloudCalendarName: String = "StudyNotch"
     var iCloudError: String     = ""

    /// Request EventKit access — call once at launch
    func requestiCloudAccess(completion: @escaping (Bool) -> Void = { _ in }) {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized {
            iCloudAuthorized = true
            completion(true)
            return
        }
        if #available(macOS 14.0, *) {
            // macOS 14 split authorized into fullAccess and writeOnly
            if status == .fullAccess || status == .writeOnly {
                 iCloudAuthorized = true
                 completion(true)
                 return
            }
        }
        
        // Prevent prompting on every single launch if the user denied it previously.
        guard status == .notDetermined else {
            iCloudAuthorized = false
            completion(false)
            return
        }
        
        log(.info, source: "iCloud", "Requesting calendar access…")
        if #available(macOS 14.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.iCloudAuthorized = granted
                    if granted {
                        self?.log(.ok, source: "iCloud", "Write-only access granted")
                    } else {
                        let msg = error?.localizedDescription ?? "Denied"
                        self?.iCloudError = msg
                        self?.log(.error, source: "iCloud", "Access denied: \(msg)")
                    }
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.iCloudAuthorized = granted
                    if granted {
                        self?.log(.ok, source: "iCloud", "Full access granted")
                    } else {
                        let msg = error?.localizedDescription ?? "Denied"
                        self?.iCloudError = msg
                        self?.log(.error, source: "iCloud", "Access denied: \(msg)")
                    }
                    completion(granted)
                }
            }
        }
    }

    /// Save a study session to iCloud calendar
    func saveSession(_ session: StudySession, completion: ((Bool) -> Void)? = nil) {
        guard iCloudAuthorized else {
            log(.warn, source: "iCloud", "Not authorized — requesting access now")
            requestiCloudAccess { [weak self] granted in
                if granted { self?.saveSession(session, completion: completion) }
                else { completion?(false) }
            }
            return
        }

        let event       = EKEvent(eventStore: eventStore)
        event.title     = "📚 \(session.subject) — StudyNotch"
        event.startDate = session.startTime
        event.endDate   = session.endTime
        event.notes     = session.notes.isEmpty
            ? "Duration: \(fmtDur(session.duration))"
            : "\(session.notes)\nDuration: \(fmtDur(session.duration))"
        event.calendar  = targetCalendar()

        do {
            try eventStore.save(event, span: .thisEvent)
            log(.ok, source: "iCloud", "Saved '\(session.subject)' \(session.startTime.formatted(.dateTime.hour().minute()))")
            completion?(true)
        } catch {
            let msg = error.localizedDescription
            iCloudError = msg
            log(.error, source: "iCloud", "Save failed: \(msg)")
            completion?(false)
        }
    }

    /// Save an exam to iCloud calendar
    func saveExam(_ exam: ExamEntry, completion: ((Bool) -> Void)? = nil) {
        guard iCloudAuthorized else { requestiCloudAccess { [weak self] ok in
            if ok { self?.saveExam(exam, completion: completion) }
        }; return }

        let event       = EKEvent(eventStore: eventStore)
        event.title     = "🎓 Exam: \(exam.subject)"
        event.startDate = exam.examTime ?? exam.date
        event.endDate   = Calendar.current.date(byAdding: .hour, value: 2, to: event.startDate)!
        event.notes     = exam.notes
        event.calendar  = targetCalendar()
        event.alarms    = [
            EKAlarm(relativeOffset: -24 * 3600),  // 1 day before
            EKAlarm(relativeOffset: -3600)         // 1 hour before
        ]

        do {
            try eventStore.save(event, span: .thisEvent)
            log(.ok, source: "iCloud", "Saved exam '\(exam.subject)'")
            completion?(true)
        } catch {
            let msg = error.localizedDescription
            log(.error, source: "iCloud", "Exam save failed: \(msg)")
            completion?(false)
        }
    }

    /// Fetch today's events from iCloud
    func fetchTodayEvents() -> [EKEvent] {
        guard iCloudAuthorized else { return [] }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        let pred  = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    // ── Google Calendar debug wrapper ─────────────────────────────────────────

    func logGoogleEvent(_ action: String, success: Bool, details: String = "") {
        log(success ? .ok : .error, source: "Google",
            "\(action)\(details.isEmpty ? "" : ": \(details)")")
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func targetCalendar() -> EKCalendar {
        // Try to find the StudyNotch calendar; create it if missing
        let name = iCloudCalendarName
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == name }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: eventStore)
        cal.title  = name
        cal.source = preferredSource()
        do {
            try eventStore.saveCalendar(cal, commit: true)
            log(.ok, source: "iCloud", "Created calendar '\(name)'")
        } catch {
            log(.warn, source: "iCloud", "Could not create calendar '\(name)': \(error.localizedDescription). Using default.")
            return eventStore.defaultCalendarForNewEvents ?? eventStore.calendars(for: .event).first!
        }
        return cal
    }

    private func preferredSource() -> EKSource {
        // Prefer iCloud, fall back to local
        let sources = eventStore.sources
        return sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? sources.first { $0.sourceType == .local }
            ?? sources.first!
    }

    private func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// ── Calendar Debug UI ─────────────────────────────────────────────────────────

struct CalendarDebugView: View {
    var svc  = CalendarDebugService.shared
    @Bindable var gcal = GoogleCalendarService.shared
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            calendarHeader
            iCloudRow
            googleRow
            if showLogs { logPanel }
        }
        .padding(14)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.12), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.2), value: showLogs)
    }

    // ── Sub-views ─────────────────────────────────────────────────────────────

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 13)).foregroundColor(.blue)
            Text("Calendar Integration").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                withAnimation { showLogs.toggle() }
            } label: {
                Text(showLogs ? "Hide Logs" : "Show Logs")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var iCloudRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            calendarStatusRow(
                icon: "cloud.fill",
                label: "iCloud Calendar",
                status: svc.iCloudAuthorized ? "Connected" : "Not authorized",
                ok: svc.iCloudAuthorized,
                action: svc.iCloudAuthorized ? nil : { svc.requestiCloudAccess() },
                actionLabel: "Connect"
            )
            if !svc.iCloudError.isEmpty {
                Label(svc.iCloudError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundColor(.red)
            }
        }
    }

    private var googleRow: some View {
        calendarStatusRow(
            icon: "g.circle.fill",
            label: "Google Calendar",
            status: gcal.isConnected
                ? "Connected"
                : gcal.lastError.isEmpty ? "Not connected" : gcal.lastError,
            ok: gcal.isConnected,
            action: gcal.isConnected ? nil : { GoogleCalendarService.shared.authenticate() },
            actionLabel: "Connect"
        )
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Debug Log")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Button("Clear") { svc.clearLogs() }
                    .font(.system(size: 9)).foregroundColor(.red.opacity(0.7)).buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(svc.logs) { entry in
                        CalendarLogRow(entry: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(height: 120)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// ── Log row helper — extracted to avoid type-checker timeout ─────────────────

struct CalendarLogRow: View {
    let entry: CalendarDebugService.LogEntry
    var body: some View {
        Text(entry.formatted)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(entry.level == .error ? .red
                             : entry.level == .ok   ? .green
                             : .secondary)
    }
}

// ── Status row helper — free function so both views can use it ────────────────

@ViewBuilder
func calendarStatusRow(icon: String, label: String, status: String, ok: Bool,
                       action: (() -> Void)?, actionLabel: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 13))
            .foregroundColor(ok ? .green : .secondary)
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 12, weight: .medium))
            Text(status).font(.system(size: 10)).foregroundColor(ok ? .green : .secondary)
        }
        Spacer()
        if let act = action {
            Button(actionLabel, action: act)
                .buttonStyle(.bordered).font(.system(size: 10)).tint(.blue)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        }
    }
}
