import Foundation
import Observation

// ── Task Type ─────────────────────────────────────────────────────────────────

enum TaskTypeKind: String, Codable, CaseIterable {
    case general    = "General"
    case video      = "Video"
    case lecture    = "Lecture"
    case assignment = "Assignment"
    case sheet      = "Sheet"

    var icon: String {
        switch self {
        case .general:    return "checkmark.circle"
        case .video:      return "video.fill"
        case .lecture:    return "doc.text.fill"
        case .assignment: return "pencil.and.list.clipboard"
        case .sheet:      return "list.number"
        }
    }

    // Unit label shown next to progress (e.g. "min", "p.", "Q")
    var unit: String {
        switch self {
        case .video:   return "min"
        case .lecture: return "p."
        case .sheet:   return "Q"
        default:       return ""
        }
    }

    // Whether this type tracks measurable progress
    var hasProgress: Bool {
        switch self {
        case .video, .lecture, .sheet: return true
        default: return false
        }
    }

    var totalLabel: String {
        switch self {
        case .video:   return "Total duration (min)"
        case .lecture: return "Total pages"
        case .sheet:   return "Total questions"
        default:       return ""
        }
    }

    var doneLabel: String {
        switch self {
        case .video:   return "Watched so far (min)"
        case .lecture: return "Current page"
        case .sheet:   return "Questions done"
        default:       return ""
        }
    }
}

// ── Priority ──────────────────────────────────────────────────────────────────

enum TaskPriority: String, Codable, CaseIterable {
    case low    = "Low"
    case medium = "Medium"
    case high   = "High"

    var xpReward: Int {
        switch self {
        case .low:    return 5
        case .medium: return 10
        case .high:   return 20
        }
    }

    var icon: String {
        switch self {
        case .low:    return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high:   return "exclamationmark.circle.fill"
        }
    }
}

// ── StudyTask ─────────────────────────────────────────────────────────────────

struct StudyTask: Identifiable, Equatable {
    var id          = UUID()
    var title       : String
    var subject     : String        = ""
    var priority    : TaskPriority  = .medium
    var dueDate     : Date?
    var isCompleted : Bool          = false
    var completedAt : Date?
    var createdAt   : Date          = Date()
    var notes       : String        = ""

    // ── Task type fields ──────────────────────────────────────────────────────
    var taskType    : TaskTypeKind  = .general
    var taskTotal   : Int           = 0
    var taskDone    : Int           = 0

    // ── Spaced Repetition (SR) fields ─────────────────────────────────────────
    var isSR             : Bool          = false
    var srInterval       : TimeInterval  = 86400  // Initial 1 day
    var lastRecall       : Date?         = nil
    var nextRecall       : Date?         = nil

    var taskProgress: Double {
        guard taskType.hasProgress, taskTotal > 0 else { return isCompleted ? 1 : 0 }
        return min(Double(taskDone) / Double(taskTotal), 1.0)
    }

    var isOverdue: Bool {
        guard let d = dueDate, !isCompleted else { return false }
        return d < Date()
    }
    var dueSoon: Bool {
        guard let d = dueDate, !isCompleted else { return false }
        return d.timeIntervalSinceNow < 86400 && d > Date()
    }
}

// ── Backward-compatible Codable ───────────────────────────────────────────────
// Old tasks.json has no taskType/taskTotal/taskDone — decodeIfPresent gives them
// safe defaults so existing tasks survive the upgrade instead of disappearing.

extension StudyTask: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, subject, priority, dueDate, isCompleted, completedAt,
             createdAt, notes, taskType, taskTotal, taskDone,
             isSR, srInterval, lastRecall, nextRecall
    }

    init(from decoder: Decoder) throws {
        let c       = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self,          forKey: .id)          ?? UUID()
        title       = try c.decode(String.self,                  forKey: .title)
        subject     = try c.decodeIfPresent(String.self,        forKey: .subject)     ?? ""
        priority    = try c.decodeIfPresent(TaskPriority.self,  forKey: .priority)    ?? .medium
        dueDate     = try c.decodeIfPresent(Date.self,          forKey: .dueDate)
        isCompleted = try c.decodeIfPresent(Bool.self,          forKey: .isCompleted) ?? false
        completedAt = try c.decodeIfPresent(Date.self,          forKey: .completedAt)
        createdAt   = try c.decodeIfPresent(Date.self,          forKey: .createdAt)   ?? Date()
        notes       = try c.decodeIfPresent(String.self,        forKey: .notes)       ?? ""
        // New fields — safe defaults for old JSON
        taskType    = try c.decodeIfPresent(TaskTypeKind.self,  forKey: .taskType)    ?? .general
        taskTotal   = try c.decodeIfPresent(Int.self,           forKey: .taskTotal)   ?? 0
        taskDone    = try c.decodeIfPresent(Int.self,           forKey: .taskDone)    ?? 0
        // SR fields
        isSR        = try c.decodeIfPresent(Bool.self,          forKey: .isSR)        ?? false
        srInterval  = try c.decodeIfPresent(TimeInterval.self,  forKey: .srInterval)  ?? 86400
        lastRecall  = try c.decodeIfPresent(Date.self,          forKey: .lastRecall)
        nextRecall  = try c.decodeIfPresent(Date.self,          forKey: .nextRecall)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,          forKey: .id)
        try c.encode(title,       forKey: .title)
        try c.encode(subject,     forKey: .subject)
        try c.encode(priority,    forKey: .priority)
        try c.encodeIfPresent(dueDate,     forKey: .dueDate)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(createdAt,   forKey: .createdAt)
        try c.encode(notes,       forKey: .notes)
        try c.encode(taskType,    forKey: .taskType)
        try c.encode(taskTotal,   forKey: .taskTotal)
        try c.encode(taskDone,    forKey: .taskDone)
        try c.encode(isSR,        forKey: .isSR)
        try c.encode(srInterval,  forKey: .srInterval)
        try c.encodeIfPresent(lastRecall, forKey: .lastRecall)
        try c.encodeIfPresent(nextRecall, forKey: .nextRecall)
    }
}

// ── TaskStore ─────────────────────────────────────────────────────────────────

@Observable
final class TaskStore {
    static let shared = TaskStore()

    var tasks: [StudyTask] = []

    private func dir() -> URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var tasksURL: URL { dir().appendingPathComponent("tasks.json") }

    init() { load() }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func add(_ task: StudyTask) {
        tasks.insert(task, at: 0)
        persist()
        NotificationService.shared.scheduleTaskReminder(task)
    }

    func update(_ task: StudyTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = task
            persist()
            NotificationService.shared.scheduleTaskReminder(task)
        }
    }

    /// Convenience: update only the progress fields without touching other state
    func updateProgress(id: UUID, done: Int) {
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].taskDone = max(0, done)
            // Auto-complete when done >= total
            if tasks[i].taskType.hasProgress,
               tasks[i].taskTotal > 0,
               tasks[i].taskDone >= tasks[i].taskTotal,
               !tasks[i].isCompleted {
                tasks[i].isCompleted = true
                tasks[i].completedAt = Date()
                GamificationStore.shared.earnXP(tasks[i].priority.xpReward,
                                                reason: "Task completed: \(tasks[i].title)")
                GamificationStore.shared.checkTaskAchievements()
            }
            persist()
        }
    }

    func delete(_ task: StudyTask) {
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func duplicate(_ task: StudyTask) {
        var copy        = task
        copy.id         = UUID()
        copy.createdAt  = Date()
        copy.isCompleted = false
        copy.completedAt = nil
        copy.taskDone   = 0
        // Prefix title so it's obvious which is the copy
        copy.title      = "Copy of \(task.title)"
        // Insert right after the original
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.insert(copy, at: idx + 1)
        } else {
            tasks.insert(copy, at: 0)
        }
        persist()
        NotificationService.shared.scheduleTaskReminder(copy)
    }

    func complete(_ task: StudyTask) {
        guard !task.isCompleted else { return }
        var t = task
        t.isCompleted = true
        t.completedAt = Date()
        update(t)
        // Award XP
        GamificationStore.shared.earnXP(t.priority.xpReward,
                                        reason: "Task completed: \(t.title)")
        GamificationStore.shared.checkTaskAchievements()
    }

    func uncomplete(_ task: StudyTask) {
        var t = task
        t.isCompleted = false
        t.completedAt = nil
        update(t)
    }

    // ── Spaced Repetition Logic ───────────────────────────────────────────────

    func recordSRRecall(id: UUID, success: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        var t = tasks[i]
        
        let now = Date()
        t.lastRecall = now
        
        if success {
            // Increase interval (fibonacci-ish or simple doubling)
            // Multiplier 2.0 for SM-2 like behavior
            t.srInterval = t.srInterval * 2.1
            // Cap at 1 year
            if t.srInterval > 365 * 86400 { t.srInterval = 365 * 86400 }
        } else {
            // Reset to 1 day if forgotten
            t.srInterval = 86400
        }
        
        t.nextRecall = now.addingTimeInterval(t.srInterval)
        tasks[i] = t
        persist()
        scheduleSRNotification(for: t)
        
        GamificationStore.shared.earnXP(success ? 15 : 5, reason: "SR Recall: \(t.title)")
    }

    func scheduleSRNotification(for task: StudyTask) {
        guard task.isSR, let next = task.nextRecall else { return }
        NotificationService.shared.scheduleSRReminder(task, at: next)
    }

    func dueSRTasks() -> [StudyTask] {
        let now = Date()
        return tasks.filter { $0.isSR && !$0.isCompleted && ($0.nextRecall ?? .distantPast) <= now }
    }

    // ── Filtered views ────────────────────────────────────────────────────────

    func pending(for subject: String? = nil) -> [StudyTask] {
        tasks.filter {
            !$0.isCompleted &&
            (subject == nil || $0.subject == subject || $0.subject.isEmpty)
        }.sorted { lhsSort($0) < lhsSort($1) }
    }

    func completed(for subject: String? = nil) -> [StudyTask] {
        tasks.filter {
            $0.isCompleted &&
            (subject == nil || $0.subject == subject || $0.subject.isEmpty)
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var overdueCount: Int { tasks.filter { $0.isOverdue }.count }
    var pendingCount: Int { tasks.filter { !$0.isCompleted }.count }

    // Sort: overdue first, then by due date, then by priority
    private func lhsSort(_ t: StudyTask) -> Double {
        var score: Double = 0
        if t.isOverdue      { score -= 1_000_000 }
        if t.dueSoon        { score -= 100_000 }
        if let d = t.dueDate { score += d.timeIntervalSinceNow }
        score -= Double(t.priority.xpReward) * 100
        return score
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? JSONDecoder().decode([StudyTask].self, from: data) {
            tasks = decoded
        }
    }
}
