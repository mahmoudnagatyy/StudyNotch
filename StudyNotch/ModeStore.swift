import Foundation
import Observation

// ── App Modes ─────────────────────────────────────────────────────────────────

enum StudyMode: String, Codable, CaseIterable {
    case college  = "College"
    case personal = "Personal Courses"
}

fileprivate struct ModeState: Codable {
    var currentMode: StudyMode = .college
    var semesterName: String = "Spring 2026"
    var semesterEnd: Date?
}

// ── College Subject ───────────────────────────────────────────────────────────

struct CollegeSubject: Codable, Identifiable {
    var id        = UUID()
    var name      : String
    var examDate  : Date?     // nil = no exam set
    var credits   : Int       = 3
    var color     : String    = "blue"  // stored as name for Codable simplicity

    var daysUntilExam: Double? {
        guard let d = examDate else { return nil }
        return d.timeIntervalSinceNow / 86400
    }
    var hoursUntilExam: Int? {
        guard let d = examDate else { return nil }
        let secs = d.timeIntervalSinceNow
        guard secs > 0 else { return nil }
        return Int(secs / 3600)
    }
    var countdownText: String? {
        guard let h = hoursUntilExam, h > 0 else {
            if let d = examDate, d.timeIntervalSinceNow < 0 { return "Exam passed" }
            return nil
        }
        let days  = h / 24
        let hours = h % 24
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(h)h"
    }
}

// ── Personal Course ───────────────────────────────────────────────────────────

enum CourseStatus: String, Codable, CaseIterable {
    case active    = "Active"
    case completed = "Completed"
    case paused    = "Paused"
    case skipped   = "Skipped"
}

struct PersonalCourse: Codable, Identifiable {
    var id          = UUID()
    var name        : String
    var field       : String       // e.g. "iOS Dev", "AI", "Design"
    var motivation  : String       // why they started it
    var startDate   : Date         = Date()
    var targetDate  : Date?        // self-imposed deadline
    var status      : CourseStatus = .active
    var progress    : Int          = 0   // 0–100%
    var aiVerdict   : String       = ""  // cached AI analysis
    var lastVerdictDate: Date?
}

// ── Mode Store ────────────────────────────────────────────────────────────────

@Observable
final class ModeStore {
    static let shared = ModeStore()

    var currentMode     : StudyMode       = .college
    var collegeSubjects : [CollegeSubject] = []
    var semesterName    : String           = "Spring 2026"
    var semesterEnd     : Date?
    var personalCourses : [PersonalCourse] = []

    // Currently active subject being studied (for notch countdown)
    var activeSubjectID : UUID?

    var activeCollegeSubject: CollegeSubject? {
        guard let id = activeSubjectID else { return nil }
        return collegeSubjects.first { $0.id == id }
    }

    private func dir() -> URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var modeURL     : URL { dir().appendingPathComponent("mode.json") }
    private var collegeURL  : URL { dir().appendingPathComponent("college.json") }
    private var coursesURL  : URL { dir().appendingPathComponent("courses.json") }

    init() { load() }

    // ── College ───────────────────────────────────────────────────────────────

    func addSubject(_ s: CollegeSubject) {
        // Prevent duplicate names (case-insensitive)
        guard !collegeSubjects.contains(where: {
            $0.name.lowercased() == s.name.lowercased()
        }) else { return }
        collegeSubjects.append(s); saveCollege()
    }
    func updateSubject(_ s: CollegeSubject) {
        if let i = collegeSubjects.firstIndex(where: { $0.id == s.id }) {
            collegeSubjects[i] = s; saveCollege()
        }
    }
    func deleteSubject(_ s: CollegeSubject) {
        collegeSubjects.removeAll { $0.id == s.id }; saveCollege()
    }

    /// Reset semester — clears subjects, keeps session history
    func resetSemester(newName: String, newEnd: Date?) {
        semesterName    = newName
        semesterEnd     = newEnd
        collegeSubjects = []
        activeSubjectID = nil
        saveCollege()
    }

    // ── Personal ──────────────────────────────────────────────────────────────

    func addCourse(_ c: PersonalCourse) {
        personalCourses.append(c); saveCourses()
    }
    func updateCourse(_ c: PersonalCourse) {
        if let i = personalCourses.firstIndex(where: { $0.id == c.id }) {
            personalCourses[i] = c; saveCourses()
        }
    }
    func deleteCourse(_ c: PersonalCourse) {
        personalCourses.removeAll { $0.id == c.id }; saveCourses()
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private var currentModeState: ModeState {
        ModeState(currentMode: currentMode, semesterName: semesterName, semesterEnd: semesterEnd)
    }

    private func saveCollege() {
        try? JSONEncoder().encode(currentModeState).write(to: modeURL, options: .atomic)
        try? JSONEncoder().encode(collegeSubjects).write(to: collegeURL, options: .atomic)
    }

    private func saveCourses() {
        try? JSONEncoder().encode(personalCourses).write(to: coursesURL, options: .atomic)
    }

    func saveMode() {
        saveCollege(); saveCourses()
    }

    private func load() {
        if let data = try? Data(contentsOf: modeURL),
           let decoded = try? JSONDecoder().decode(ModeState.self, from: data) {
            currentMode  = decoded.currentMode
            semesterName = decoded.semesterName
            semesterEnd  = decoded.semesterEnd
        }
        if let data = try? Data(contentsOf: collegeURL),
           let decoded = try? JSONDecoder().decode([CollegeSubject].self, from: data) {
            // Deduplicate by ID to prevent double-loading
            var seen = Set<UUID>()
            collegeSubjects = decoded.filter { seen.insert($0.id).inserted }
        }
        if let data = try? Data(contentsOf: coursesURL),
           let decoded = try? JSONDecoder().decode([PersonalCourse].self, from: data) {
            var seen = Set<UUID>()
            personalCourses = decoded.filter { seen.insert($0.id).inserted }
        }
    }

    // ── Helpers for AI ────────────────────────────────────────────────────────

    var personalCourseSummaryForAI: String {
        personalCourses.map { c in
            "Course: \(c.name) | Field: \(c.field) | Status: \(c.status.rawValue) | Progress: \(c.progress)% | Started: \(c.startDate.formatted(.dateTime.month().day())) | Motivation: \(c.motivation)"
        }.joined(separator: "\n")
    }
}
