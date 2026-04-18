import Foundation
import Observation
import SwiftUI
import Observation
import UserNotifications
import AppKit

// ── Notification Service ──────────────────────────────────────────────────────
//
//  Handles all UNUserNotification scheduling for StudyNotch:
//
//   1. Exam countdowns  — UNCalendarNotificationTrigger alerts at 7d/3d/1d/0d
//   2. Task reminders   — UNCalendarNotificationTrigger banners 1 day before due
//   3. Smart study check— Timer-based: if no session today by configuredHour,
//                         fires a local notification (menu-bar app = always running)
//
//  Settings are stored in UserDefaults and exposed as  for SwiftUI.
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    // ── Persisted settings ────────────────────────────────────────────────────
     var examAlertsEnabled    : Bool = true
     var taskRemindersEnabled : Bool = true
     var smartReminderEnabled : Bool = true
     var smartReminderHour    : Int  = 20   // 8 PM default
     var srRemindersEnabled   : Bool = true

    private let kExamAlerts    = "notif_exam_alerts"
    private let kTaskReminders = "notif_task_reminders"
    private let kSmartEnabled  = "notif_smart_enabled"
    private let kSmartHour     = "notif_smart_hour"
    private let kSmartLastFire = "notif_smart_last_fire"
    private let kSRReminders   = "notif_sr_reminders"

    // ── Internal state ────────────────────────────────────────────────────────
    private var checkTimer : Timer?
     var permissionGranted: Bool = false

    // ── Boot ──────────────────────────────────────────────────────────────────

    override init() {
        super.init()
        loadSettings()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func start() {
        requestPermission { [weak self] granted in
            guard granted else { return }
            self?.permissionGranted = true
            self?.startSmartTimer()
            self?.rescheduleAllExams()
            self?.rescheduleAllTasks()
            self?.rescheduleAllSR()
        }
    }

    // ── Permission ────────────────────────────────────────────────────────────

    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.permissionGranted = granted
                completion(granted)
            }
        }
    }

    // ── UNUserNotificationCenterDelegate ─────────────────────────────────────
    // Show notification even when app is in foreground

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // ── 1. Exam Countdown Alerts ──────────────────────────────────────────────
    //
    //  Schedules UNCalendarNotificationTrigger alerts at:
    //    7 days before  → banner
    //    3 days before  → alert
    //    1 day before   → alert
    //    day-of         → alert
    //
    //  Calling this again for the same exam safely overwrites old requests
    //  because we use deterministic identifier strings.

    func scheduleExamCountdown(_ exam: ExamEntry) {
        guard examAlertsEnabled else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()

        let triggers: [(daysBefore: Int, title: String, body: String, isAlert: Bool)] = [
            (7, "📚 Exam in 7 Days",   "\(exam.subject) — start your deep review now",           false),
            (3, "⚠️ Exam in 3 Days",   "\(exam.subject) — intensive prep time, 3 days left",     true),
            (1, "🚨 Exam Tomorrow",    "\(exam.subject) exam is tomorrow — final revision!",      true),
            (0, "⏰ Exam Today!",       "\(exam.subject) exam is today — you've got this! 🎓",    true),
        ]

        for t in triggers {
            guard let fireDate = Calendar.current.date(
                byAdding: .day, value: -t.daysBefore, to: exam.date
            ), fireDate > Date() else { continue }

            let content              = UNMutableNotificationContent()
            content.title            = t.title
            content.body             = t.body
            content.sound            = .default
            if t.isAlert {
                if #available(macOS 12.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
            }

            let comps   = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id      = "exam_\(exam.id.uuidString)_\(t.daysBefore)d"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))

            // Also push to iPhone if the fire date is within 5 minutes of now
            // (i.e., this notification is firing right now, not pre-scheduled for the future)
            if abs(fireDate.timeIntervalSinceNow) < 300 {
                let priority: NtfyPriority = t.isAlert ? .urgent : .high
                NtfyService.shared.send(title: t.title, body: t.body,
                                        priority: priority, tags: ["books", "alarm"])
            }
        }
    }

    func cancelExamCountdown(_ exam: ExamEntry) {
        let ids = [7,3,1,0].map { "exam_\(exam.id.uuidString)_\($0)d" }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func rescheduleAllExams() {
        guard examAlertsEnabled else { return }
        for exam in SubjectStore.shared.exams { scheduleExamCountdown(exam) }
    }

    // ── 2. Task Due Reminders ─────────────────────────────────────────────────
    //
    //  Banner at 9:00 AM the day before the due date.
    //  Identifier is deterministic → safe to call repeatedly.

    func scheduleTaskReminder(_ task: StudyTask) {
        guard taskRemindersEnabled, !task.isCompleted, let due = task.dueDate else { return }

        // Day before at 9 AM
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: due) else { return }
        var comps      = Calendar.current.dateComponents([.year,.month,.day], from: dayBefore)
        comps.hour     = 9; comps.minute = 0; comps.second = 0

        guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { return }

        let content       = UNMutableNotificationContent()
        content.title     = "📋 Task Due Tomorrow"
        let sub           = task.subject.isEmpty ? "" : " [\(task.subject)]"
        content.body      = "\(task.title)\(sub) — due \(due.formatted(.dateTime.month(.abbreviated).day()))"
        content.sound     = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: fireDate),
            repeats: false
        )
        let id = "task_\(task.id.uuidString)_1d"
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancelTaskReminder(_ task: StudyTask) {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["task_\(task.id.uuidString)_1d"])
        }
    }

    func rescheduleAllTasks() {
        guard taskRemindersEnabled else { return }
        for task in TaskStore.shared.tasks where !task.isCompleted {
            scheduleTaskReminder(task)
        }
    }

    // ── 3. Spaced Repetition Reminders ────────────────────────────────────────

    func scheduleSRReminder(_ task: StudyTask, at: Date) {
        guard srRemindersEnabled, task.isSR, !task.isCompleted, at > Date() else { return }

        let content   = UNMutableNotificationContent()
        content.title = "🧠 Time for Recall"
        content.body  = "Spaced Repetition: \(task.title) is ready for review."
        content.sound = .default
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let comps     = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: at)
        let trigger   = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id        = "sr_\(task.id.uuidString)"
        
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func cancelSRReminder(_ task: StudyTask) {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["sr_\(task.id.uuidString)"])
        }
    }

    func rescheduleAllSR() {
        guard srRemindersEnabled else { return }
        for task in TaskStore.shared.tasks where task.isSR && !task.isCompleted {
            if let next = task.nextRecall {
                scheduleSRReminder(task, at: next)
            }
        }
    }

    // ── 4. Smart Study Reminder ───────────────────────────────────────────────
    //
    //  A Timer fires every minute. When the clock matches `smartReminderHour`
    //  AND today's total study time is 0, we fire a local notification and
    //  record today's date so it only fires once per day.

    func startSmartTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkSmartReminder()
        }
        // Also check immediately on start
        checkSmartReminder()
    }

    private func checkSmartReminder() {
        guard smartReminderEnabled else { return }
        let now = Date()
        let cal = Calendar.current
        guard cal.component(.hour, from: now) == smartReminderHour else { return }

        // Only fire once per calendar day
        let todayKey = cal.startOfDay(for: now).timeIntervalSince1970
        let lastFire = UserDefaults.standard.double(forKey: kSmartLastFire)
        guard lastFire != todayKey else { return }

        // Only fire if no study today
        let todayTotal = SessionStore.shared.sessions
            .filter { cal.isDateInToday($0.date) }
            .reduce(0.0) { $0 + $1.duration }
        guard todayTotal < 60 else { return }   // less than 1 minute = effectively zero

        // Mark fired for today
        UserDefaults.standard.set(todayKey, forKey: kSmartLastFire)

        // Fire immediately as a local notification
        let content       = UNMutableNotificationContent()
        content.title     = "📚 Time to Study!"
        let pending       = TaskStore.shared.tasks.filter { !$0.isCompleted }.count
        let taskHint      = pending > 0 ? " You have \(pending) pending task\(pending == 1 ? "" : "s")." : ""
        content.body      = "You haven't studied today yet.\(taskHint) Open StudyNotch to start a session."
        content.sound     = .default

        let id = "smart_study_\(Int(todayKey))"
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }

        // Mirror to iPhone
        NtfyService.shared.send(
            title    : "📚 Time to Study!",
            body     : content.body,
            priority : .high,
            tags     : ["books", "spiral_notepad"]
        )
    }

    // ── Settings persistence ──────────────────────────────────────────────────

    func saveSettings() {
        UserDefaults.standard.set(examAlertsEnabled,    forKey: kExamAlerts)
        UserDefaults.standard.set(taskRemindersEnabled, forKey: kTaskReminders)
        UserDefaults.standard.set(smartReminderEnabled, forKey: kSmartEnabled)
        UserDefaults.standard.set(smartReminderHour,    forKey: kSmartHour)
        UserDefaults.standard.set(srRemindersEnabled,   forKey: kSRReminders)
        // Re-apply after save
        if smartReminderEnabled { startSmartTimer() } else { checkTimer?.invalidate() }
        if examAlertsEnabled    { rescheduleAllExams() }
        if taskRemindersEnabled { rescheduleAllTasks() }
        if srRemindersEnabled   { rescheduleAllSR() }
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        examAlertsEnabled    = d.object(forKey: kExamAlerts)    as? Bool ?? true
        taskRemindersEnabled = d.object(forKey: kTaskReminders) as? Bool ?? true
        smartReminderEnabled = d.object(forKey: kSmartEnabled)  as? Bool ?? true
        smartReminderHour    = d.integer(forKey: kSmartHour).nonZeroOr(20)
        srRemindersEnabled   = d.object(forKey: kSRReminders)   as? Bool ?? true
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

// ── Notification Settings View ────────────────────────────────────────────────
//  Embedded inside StudyPlanView's settings tab.

struct NotificationSettingsSection: View {
    @Bindable var svc = NotificationService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 12)).foregroundColor(.blue)
                }
                Text("Notifications").font(.system(size: 13, weight: .semibold))
                Spacer()
                if !svc.permissionGranted {
                    Button("Grant Permission") { svc.requestPermission() }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                        .tint(.blue)
                }
            }

            if !svc.permissionGranted {
                Label("macOS notifications are not authorized. Click \"Grant Permission\" above.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            Divider()

            // ── Exam Countdowns ────────────────────────────────────────────
            toggleRow(
                icon: "alarm.fill", color: .red,
                title: "Exam countdown alerts",
                subtitle: "Alert at 7d, 3d, 1d and day-of for each exam",
                binding: $svc.examAlertsEnabled
            )

            // ── Sound Theme ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13))
                        .foregroundColor(.purple)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound Theme").font(.system(size: 12, weight: .medium))
                        Text("Choose your session sounds").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { SoundService.shared.theme },
                        set: { SoundService.shared.theme = $0 }
                    )) {
                        ForEach(SoundTheme.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // ── Task reminders ─────────────────────────────────────────────
            toggleRow(
                icon: "checklist", color: .orange,
                title: "Task due reminders",
                subtitle: "Banner at 9 AM the day before a task is due",
                binding: $svc.taskRemindersEnabled
            )

            // ── Spaced Repetition ──────────────────────────────────────────
            toggleRow(
                icon: "brain.head.profile", color: .blue,
                title: "Spaced Repetition recalls",
                subtitle: "Notification when a task is due for memory review",
                binding: $svc.srRemindersEnabled
            )

            // ── Smart study reminder ───────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                toggleRow(
                    icon: "sparkles", color: .green,
                    title: "Smart study reminder",
                    subtitle: "Fires if you haven't studied at all by the chosen hour",
                    binding: $svc.smartReminderEnabled
                )

                if svc.smartReminderEnabled {
                    HStack(spacing: 10) {
                        Text("Remind me at")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.leading, 36)

                        Picker("", selection: $svc.smartReminderHour) {
                            ForEach(6..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Divider()

            Button {
                svc.saveSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                    Text("Save & Apply").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color(red: 0.2, green: 1.0, blue: 0.5))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.12), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: svc.smartReminderEnabled)
    }

    func toggleRow(icon: String, color: Color, title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    func hourLabel(_ h: Int) -> String {
        let suffix = h < 12 ? "AM" : "PM"
        let display = h <= 12 ? h : h - 12
        return "\(display):00 \(suffix)"
    }
}
