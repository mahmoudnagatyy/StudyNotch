import Foundation
import Observation

// ── Data Model ────────────────────────────────────────────────────────────────

struct StudySession: Codable, Identifiable {
    var id           = UUID()
    var subject      : String
    var notes        : String       // plain text (for search/AI/Telegram/Notion)
    var notesRTF     : Data? = nil  // RTF data (for rich display with colors/images)
    var difficulty   : Int
    var mode         : String        = StudyMode.college.rawValue
    var date         : Date
    var startTime    : Date
    var endTime      : Date
    var duration     : TimeInterval
    var distractions : [DistractionEvent] = []
    var pauses       : [PauseInterval]    = []
    var isManual     : Bool          = false   // true when entered without a live timer
    var appUsage     : [String: TimeInterval] = [:] // bundleID -> total seconds used

    // Custom decode so old sessions missing `isManual` still load fine
    init(id: UUID = UUID(), subject: String, notes: String, difficulty: Int,
         mode: String = StudyMode.college.rawValue, date: Date,
         startTime: Date, endTime: Date, duration: TimeInterval,
         distractions: [DistractionEvent] = [], pauses: [PauseInterval] = [],
         isManual: Bool = false, appUsage: [String: TimeInterval] = [:]) {
        self.id = id; self.subject = subject; self.notes = notes
        self.difficulty = difficulty; self.mode = mode; self.date = date
        self.startTime = startTime; self.endTime = endTime; self.duration = duration
        self.distractions = distractions; self.pauses = pauses; self.isManual = isManual
        self.appUsage = appUsage
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, notes, difficulty, mode, date, startTime, endTime,
             duration, distractions, pauses, isManual, appUsage
    }

    init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self,               forKey: .id)           ?? UUID()
        subject      = try c.decode(String.self,                       forKey: .subject)
        notes        = try c.decodeIfPresent(String.self,              forKey: .notes)        ?? ""
        difficulty   = try c.decodeIfPresent(Int.self,                 forKey: .difficulty)   ?? 0
        mode         = try c.decodeIfPresent(String.self,              forKey: .mode)         ?? StudyMode.college.rawValue
        date         = try c.decode(Date.self,                         forKey: .date)
        startTime    = try c.decode(Date.self,                         forKey: .startTime)
        endTime      = try c.decode(Date.self,                         forKey: .endTime)
        duration     = try c.decode(TimeInterval.self,                 forKey: .duration)
        distractions = try c.decodeIfPresent([DistractionEvent].self,  forKey: .distractions) ?? []
        pauses       = try c.decodeIfPresent([PauseInterval].self,     forKey: .pauses)       ?? []
        isManual     = try c.decodeIfPresent(Bool.self,                forKey: .isManual)     ?? false
        appUsage     = try c.decodeIfPresent([String: TimeInterval].self, forKey: .appUsage)  ?? [:]
    }
}

// ── Store ─────────────────────────────────────────────────────────────────────

// ── Quick Note ────────────────────────────────────────────────────────────────

struct QuickNote: Codable, Identifiable {
    var id             = UUID()
    var subject        : String
    var text           : String
    var date           : Date   = Date()
    var sentToTelegram : Bool   = false
    var imageData      : Data?  = nil   // optional pasted image (PNG)


}

@Observable
final class SessionStore {
    static let shared = SessionStore()

var sessions : [StudySession] = []
    var knownSubjects : [String] = []
    var quickNotes : [QuickNote] = []


    private func dir() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let d = support.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var sessionsURL : URL { dir().appendingPathComponent("sessions.json") }
private var subjectsURL : URL { dir().appendingPathComponent("subjects.json") }
    private var notesURL : URL { dir().appendingPathComponent("quick_notes.json") }
    private let legacyAppGroupID = "group.nagaty.studynotch"

    init() { load() }

    // ── CRUD ──────────────────────────────────────────────────────────────────

    func save(_ session: StudySession) {
        // Name awareness: check case-insensitively — if "Cyber Security" exists,
        // don't add "cyber security" or "CYBER SECURITY" as a separate entry.
        // Normalise to the canonical existing name if a case-variant exists.
        var sessionToSave = session
        if let canonical = knownSubjects.first(where: {
            $0.lowercased() == session.subject.lowercased()
        }) {
            // Use the existing canonical capitalisation
            sessionToSave = StudySession(
                id: session.id, subject: canonical, notes: session.notes,
                difficulty: session.difficulty, mode: session.mode,
                date: session.date, startTime: session.startTime,
                endTime: session.endTime, duration: session.duration,
                distractions: session.distractions, pauses: session.pauses,
                isManual: session.isManual
            )
        } else {
            // New subject — add it
            knownSubjects.insert(session.subject, at: 0)
        }
        sessions.insert(sessionToSave, at: 0)
        sortSessionsInPlace()
        persistSessions()
        persistSubjects()
        CloudSyncService.shared.pushSession(session)
        // Google Calendar auto-sync — only push planned (future-dated) sessions
        if GoogleCalendarService.shared.autoSync && sessionToSave.startTime > Date() {
            GoogleCalendarService.shared.pushSession(sessionToSave) { _ in }
        }
        // Award XP and check achievements
        GamificationStore.shared.processSession(session)
        // Update streak
        StreakStore.shared.rebuild()
    }

    func update(_ session: StudySession) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i] = session
        sortSessionsInPlace()
        persistSessions()
    }

    func delete(_ session: StudySession) {
        sessions.removeAll { $0.id == session.id }
        persistSessions()
        // Deduct XP earned from this session
        let xp = GamificationStore.shared.xpForSession(session)
        GamificationStore.shared.deductXP(xp, reason: "Deleted session: \(session.subject)")
    }

    func deleteAll() {
        sessions.removeAll()
        persistSessions()
    }

    // MARK: Focus Score Enhancements

    func averageFocusScore(for subject: String, in range: DateInterval? = nil) -> Int {
        var relevant = sessions.filter { $0.subject == subject }
        if let r = range {
            relevant = relevant.filter { r.contains($0.date) }
        }
        guard !relevant.isEmpty else { return 0 }
        let total = relevant.reduce(0) { $0 + $1.focusScore }
        return total / relevant.count
    }

    func focusScoreHistory(for subject: String, limit: Int = 10) -> [StudySession] {
        let relevant = sessions.filter { $0.subject == subject }
        // sessions are expected to be sorted newest first
        return Array(relevant.prefix(limit)).reversed() // Return oldest-to-newest for charts
    }
    
    func focusTrend(for subject: String) -> Double {
        let history = focusScoreHistory(for: subject, limit: 10)
        guard history.count > 1 else { return 0 }
        let firstHalf = history.prefix(history.count / 2)
        let secondHalf = history.suffix(history.count - history.count / 2)
        
        let firstAvg = firstHalf.reduce(0) { $0 + $1.focusScore } / max(1, firstHalf.count)
        let secondAvg = secondHalf.reduce(0) { $0 + $1.focusScore } / max(1, secondHalf.count)
        
        return Double(secondAvg - firstAvg)
    }

    // ── CSV Export ────────────────────────────────────────────────────────────

    func exportToCSV() -> String {
        var csv = "Subject,Date,Start,End,Duration(min),Distractions,Pauses,FocusScore,Difficulty,Mode,Notes\n"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        
        for s in sessions {
            let row = [
                s.subject,
                fmt.string(from: s.date),
                fmt.string(from: s.startTime),
                fmt.string(from: s.endTime),
                String(format: "%.1f", s.duration / 60.0),
                "\(s.distractions)",
                "\(s.pauses)",
                "\(s.focusScore)",
                "\(s.difficulty)",
                s.mode == "0" ? "College" : "Personal",
                "\"\(s.notes.replacingOccurrences(of: "\"", with: "\"\""))\""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        return csv
    }

    // ── Smart Insights ────────────────────────────────────────────────────────

    func bestFocusHour() -> Int? {
        var hourScores: [Int: (total: Int, count: Int)] = [:]
        for s in sessions {
            let hour = Calendar.current.component(.hour, from: s.startTime)
            let current = hourScores[hour, default: (0, 0)]
            hourScores[hour] = (current.total + s.focusScore, current.count + 1)
        }
        return hourScores.max { a, b in
            (Double(a.value.total) / Double(a.value.count)) < (Double(b.value.total) / Double(b.value.count))
        }?.key
    }

    func mostProductiveDay() -> Int? {
        var daySeconds: [Int: TimeInterval] = [:]
        for s in sessions {
            let day = Calendar.current.component(.weekday, from: s.startTime)
            daySeconds[day, default: 0] += s.duration
        }
        return daySeconds.max { $0.value < $1.value }?.key
    }

    func subjectsNeedingAttention() -> [String] {
        let all = Array(knownSubjects)
        let now = Date()
        var needs: [String] = []
        
        for sub in all {
            let lastSession = sessions.first { $0.subject == sub }
            if let last = lastSession {
                let daysSince = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
                if daysSince > 3 {
                    needs.append(sub)
                }
            } else {
                needs.append(sub) // Never studied
            }
        }
        return needs
    }

    // ── Subject management ────────────────────────────────────────────────────

    func addKnownSubject(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Prevent case-insensitive duplicates
        guard !knownSubjects.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return }
        knownSubjects.insert(trimmed, at: 0)
        persistSubjects()
    }

    func removeKnownSubject(_ name: String) {
        knownSubjects.removeAll { $0 == name }
        persistSubjects()
    }

    // ── Quick Notes ───────────────────────────────────────────────────────────

    func saveQuickNote(_ note: QuickNote) {
        quickNotes.insert(note, at: 0)
        persistNotes()
    }

    func deleteQuickNote(_ note: QuickNote) {
        quickNotes.removeAll { $0.id == note.id }
        persistNotes()
    }

    private func persistNotes() {
        guard let data = try? JSONEncoder().encode(quickNotes) else { return }
        try? data.write(to: notesURL, options: .atomic)
    }

    func persistPublic() { persistSessions() }

    private func persistSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }

    private func persistSubjects() {
        guard let data = try? JSONEncoder().encode(knownSubjects) else { return }
        try? data.write(to: subjectsURL, options: .atomic)
    }

    private func normalizedSubject(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sortSessionsInPlace() {
        sessions.sort { a, b in
            if a.startTime != b.startTime { return a.startTime > b.startTime }
            if a.endTime   != b.endTime   { return a.endTime   > b.endTime }
            return a.id.uuidString > b.id.uuidString
        }
    }

    private func decodeSessionsFile(at url: URL) -> [StudySession] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([StudySession].self, from: data)
        else { return [] }
        return decoded
    }

    private func legacySessionCandidateURLs() -> [URL] {
        let fm = FileManager.default
        let groupRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(legacyAppGroupID)/StudyNotch", isDirectory: true)

        var urls: [URL] = [groupRoot.appendingPathComponent("sessions.json")]
        if let dirs = try? fm.contentsOfDirectory(at: groupRoot,
                                                  includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles]) {
            let backups = dirs.filter {
                $0.lastPathComponent.hasPrefix("backup-restore-")
            }.map { $0.appendingPathComponent("sessions.json") }
            urls.append(contentsOf: backups)
        }
        return urls.filter { $0 != sessionsURL && fm.fileExists(atPath: $0.path) }
    }

    private func backupSessionsBeforeRecovery() {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return }
        let ts = Int(Date().timeIntervalSince1970)
        let backup = dir().appendingPathComponent("sessions-backup-before-recovery-\(ts).json")
        do {
            try FileManager.default.copyItem(at: sessionsURL, to: backup)
            print("📦 Backed up sessions to \(backup.path)")
        } catch {
            print("⚠️ Could not create pre-recovery backup: \(error.localizedDescription)")
        }
    }

    private func recoverMissingSessionsFromLegacyStores() {
        let candidates = legacySessionCandidateURLs()
        guard !candidates.isEmpty else { return }

        var merged: [UUID: StudySession] = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var imported = 0
        var replaced = 0

        for url in candidates {
            let legacySessions = decodeSessionsFile(at: url)
            guard !legacySessions.isEmpty else { continue }
            for candidate in legacySessions {
                if let existing = merged[candidate.id] {
                    // Keep the richer/latest record if duplicate IDs diverge.
                    if candidate.endTime > existing.endTime || candidate.duration > existing.duration {
                        merged[candidate.id] = candidate
                        replaced += 1
                    }
                } else {
                    merged[candidate.id] = candidate
                    imported += 1
                }
            }
        }

        guard imported > 0 || replaced > 0 else { return }
        backupSessionsBeforeRecovery()
        sessions = Array(merged.values)
        sortSessionsInPlace()

        var subjectSet = Set(knownSubjects.map(normalizedSubject))
        for subject in sessions.map(\.subject) {
            let key = normalizedSubject(subject)
            if !subjectSet.contains(key) {
                knownSubjects.append(subject)
                subjectSet.insert(key)
            }
        }

        persistSessions()
        persistSubjects()
        print("✅ Recovered \(imported) missing sessions (\(replaced) replaced) from legacy stores.")
    }

    private func load() {
        if let data = try? Data(contentsOf: sessionsURL),
           let decoded = try? JSONDecoder().decode([StudySession].self, from: data) {
            sessions = decoded
        }
        if let data = try? Data(contentsOf: subjectsURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            knownSubjects = decoded
        } else {
            knownSubjects = Array(Dictionary(grouping: sessions, by: \.subject)
                .sorted { $0.value.count > $1.value.count }.map(\.key))
        }
        recoverMissingSessionsFromLegacyStores()
        sortSessionsInPlace()
        if let data = try? Data(contentsOf: notesURL),
           let decoded = try? JSONDecoder().decode([QuickNote].self, from: data) {
            quickNotes = decoded
        }
    }

    // ── Smart suggestions ─────────────────────────────────────────────────────

    func rankedSuggestions(filter: String = "") -> [String] {
        let input = filter.trimmingCharacters(in: .whitespaces).lowercased()
        var freq  : [String: Int]          = [:]
        var recent: [String: TimeInterval] = [:]
        for s in sessions {
            freq[s.subject, default: 0] += 1
            let t = s.startTime.timeIntervalSince1970
            if (recent[s.subject] ?? 0) < t { recent[s.subject] = t }
        }
        let now = Date().timeIntervalSince1970

        // Deduplicate knownSubjects case-insensitively — keep first (canonical) occurrence
        var seen = Set<String>()
        let deduped = knownSubjects.filter { seen.insert($0.lowercased()).inserted }

        let scored = deduped.map { name -> (String, Double) in
            var score = Double(freq[name] ?? 0)
            if let last = recent[name] {
                let age = now - last
                if age < 7*86400 { score += 3 } else if age < 30*86400 { score += 1 }
            }
            return (name, score)
        }.sorted { $0.1 > $1.1 }
        if input.isEmpty { return scored.map(\.0) }
        return scored.filter { $0.0.lowercased().contains(input) }.map(\.0)
    }

    /// Merge case-duplicate subjects — call once to clean up existing data
    func deduplicateSubjects() {
        var canonical: [String: String] = [:]   // lowercased → first seen
        for sub in knownSubjects {
            let key = sub.lowercased()
            if canonical[key] == nil { canonical[key] = sub }
        }
        // Rebuild knownSubjects with only canonical names
        var seen = Set<String>()
        knownSubjects = knownSubjects.filter { seen.insert($0.lowercased()).inserted }
        // Remap sessions to canonical names
        for i in sessions.indices {
            let key = sessions[i].subject.lowercased()
            if let canon = canonical[key], canon != sessions[i].subject {
                sessions[i] = StudySession(
                    id: sessions[i].id, subject: canon, notes: sessions[i].notes,
                    difficulty: sessions[i].difficulty, mode: sessions[i].mode,
                    date: sessions[i].date, startTime: sessions[i].startTime,
                    endTime: sessions[i].endTime, duration: sessions[i].duration,
                    distractions: sessions[i].distractions, pauses: sessions[i].pauses,
                    isManual: sessions[i].isManual
                )
            }
        }
        persistSessions()
        persistSubjects()
    }

    // ── Analytics helpers ─────────────────────────────────────────────────────

    var todayTotal: TimeInterval {
        sessions.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.duration }
    }

    var byDay: [(day: String, sessions: [StudySession])] {
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
        var groups: [(String, [StudySession])] = []; var seen: [String: Int] = [:]
        for s in sessions {
            let key = fmt.string(from: s.date)
            if let idx = seen[key] { groups[idx].1.append(s) }
            else { seen[key] = groups.count; groups.append((key, [s])) }
        }
        return groups.map { ($0.0, $0.1) }
    }

    var subjectTotals: [(subject: String, total: TimeInterval)] {
        var map: [String: TimeInterval] = [:]
        sessions.forEach { map[$0.subject, default: 0] += $0.duration }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var avgDifficulty: Double {
        let rated = sessions.filter { $0.difficulty > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.map(\.difficulty).reduce(0,+)) / Double(rated.count)
    }

    // ── AI Context Builders ───────────────────────────────────────────────────
    //
    //  These feed every AI prompt. They deliberately include subjects with ZERO
    //  sessions, all pending tasks, exam dates, and weekly goals — so the AI
    //  can give advice beyond just what has already been studied.

    /// Full context for schedule/report prompts — everything the AI needs
    var fullContextForAI: String {
        var lines: [String] = []

        // ── 1. All known subjects (with or without sessions) ──────────────────
        let subjectStore = SubjectStore.shared
        let modeStore    = ModeStore.shared
        var allSubjects  = knownSubjects
        for s in modeStore.collegeSubjects.map(\.name) {
            if !allSubjects.contains(s) { allSubjects.append(s) }
        }
        for s in subjectStore.metas.map(\.name) {
            if !allSubjects.contains(s) { allSubjects.append(s) }
        }

        lines.append("=== SUBJECTS (\(allSubjects.count) total) ===")
        for sub in allSubjects {
            let totalSecs = sessions.filter { $0.subject == sub }.reduce(0.0) { $0 + $1.duration }
            let weekSecs  = subjectStore.actualHoursThisWeek(subject: sub, sessions: sessions) * 3600
            let weekGoal  = subjectStore.weeklyGoals.first { $0.subject == sub }?.weeklyHours ?? 0
            let dailyGoal = subjectStore.goalHours(for: sub)
            let exam      = subjectStore.exams.filter { $0.subject == sub }
                                              .sorted { $0.daysUntil < $1.daysUntil }.first
            var parts: [String] = ["\(sub)"]
            parts.append("total_studied: \(Int(totalSecs/60))min")
            parts.append("this_week: \(String(format:"%.1f", weekSecs/3600))h / goal \(String(format:"%.1f", weekGoal))h")
            parts.append("daily_goal: \(String(format:"%.1f", dailyGoal))h")
            if let e = exam {
                let d = Int(e.daysUntil)
                parts.append("EXAM in \(d)d (\(e.date.formatted(.dateTime.month(.abbreviated).day())))")
            } else {
                parts.append("no_exam_set")
            }
            if totalSecs == 0 { parts.append("⚠️ NOT STUDIED YET") }
            lines.append("  • " + parts.joined(separator: " | "))
        }

        // ── 2. Pending tasks ──────────────────────────────────────────────────
        let taskStore   = TaskStore.shared
        let pending     = taskStore.tasks.filter { !$0.isCompleted }
        let overdue     = pending.filter { $0.isOverdue }
        lines.append("\n=== PENDING TASKS (\(pending.count), \(overdue.count) overdue) ===")
        if pending.isEmpty {
            lines.append("  (none)")
        } else {
            for t in pending.prefix(20) {
                var parts = ["\"\(t.title)\""]
                if !t.subject.isEmpty { parts.append("[\(t.subject)]") }
                parts.append("type:\(t.taskType.rawValue)")
                if t.taskType.hasProgress && t.taskTotal > 0 {
                    parts.append("progress:\(t.taskDone)/\(t.taskTotal)\(t.taskType.unit)")
                }
                if let d = t.dueDate {
                    parts.append(t.isOverdue ? "⚠️ OVERDUE since \(d.formatted(.dateTime.month(.abbreviated).day()))"
                                             : "due:\(d.formatted(.dateTime.month(.abbreviated).day()))")
                }
                parts.append("priority:\(t.priority.rawValue)")
                lines.append("  • " + parts.joined(separator: " "))
            }
        }

        // ── 3. Recent session history (last 30) ───────────────────────────────
        let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
        lines.append("\n=== RECENT SESSIONS (last \(min(sessions.count, 30))) ===")
        if sessions.isEmpty {
            lines.append("  (no sessions yet)")
        } else {
            for s in sessions.prefix(30) {
                var row = "[\(fmt.string(from: s.date))] \(s.subject) — \(Int(s.duration/60))min"
                if s.difficulty > 0 { row += ", diff \(s.difficulty)/5" }
                if s.distractions.count > 0 { row += ", distractions: \(s.distractions.count)" }
                if !s.notes.isEmpty { row += ", notes: \(s.notes)" }
                lines.append("  " + row)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Compact session-only summary (used where full context would be too long)
    var summaryForAI: String {
        let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
        return sessions.prefix(30).map { s in
            "[\(fmt.string(from: s.date))] \(s.subject) — \(Int(s.duration/60))min, diff \(s.difficulty)/5, distractions: \(s.distractions.count)\(s.notes.isEmpty ? "" : ", notes: \(s.notes)")"
        }.joined(separator: "\n")
    }

    // ── Study style data for AI ───────────────────────────────────────────────

    var styleDataForAI: String {
        let fmt = DateFormatter(); fmt.dateStyle = .short
        let cal = Calendar.current
        return sessions.prefix(50).map { s in
            let hour      = cal.component(.hour, from: s.startTime)
            let weekday   = cal.weekdaySymbols[cal.component(.weekday, from: s.startTime) - 1]
            let timeOfDay = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
            return "\(s.subject) | \(weekday) \(timeOfDay) (\(hour):00) | \(Int(s.duration/60))min | diff \(s.difficulty)/5 | \(s.distractions.count) distractions"
        }.joined(separator: "\n")
    }
}
