import Foundation
import Observation
import SwiftUI

// ── Subject Color Palette ─────────────────────────────────────────────────────

let subjectPalette: [Color] = [
    Color(red: 0.20, green: 0.78, blue: 1.00),  //  0  sky blue
    Color(red: 0.35, green: 1.00, blue: 0.55),  //  1  mint green
    Color(red: 1.00, green: 0.55, blue: 0.20),  //  2  orange
    Color(red: 0.85, green: 0.35, blue: 1.00),  //  3  purple
    Color(red: 1.00, green: 0.30, blue: 0.45),  //  4  red-pink
    Color(red: 1.00, green: 0.88, blue: 0.20),  //  5  yellow
    Color(red: 0.30, green: 0.60, blue: 1.00),  //  6  blue
    Color(red: 0.20, green: 1.00, blue: 0.80),  //  7  teal
    Color(red: 1.00, green: 0.42, blue: 0.30),  //  8  coral
    Color(red: 0.55, green: 1.00, blue: 0.20),  //  9  lime
    Color(red: 1.00, green: 0.24, blue: 0.76),  // 10  hot pink
    Color(red: 0.48, green: 0.38, blue: 1.00),  // 11  indigo
    Color(red: 1.00, green: 0.72, blue: 0.10),  // 12  amber
    Color(red: 0.10, green: 0.90, blue: 0.90),  // 13  aqua
]

let subjectPaletteHex: [String] = [
    "#33C7FF", "#59FF8C", "#FF8C33", "#D959FF",
    "#FF4D72", "#FFE033", "#4D99FF", "#33FFCC",
    "#FF6B4D", "#8CFF33", "#FF3DC2", "#7A61FF",
    "#FFB81A", "#1AE5E5"
]

// ── Exam Entry ────────────────────────────────────────────────────────────────

struct ExamEntry: Codable, Identifiable {
    var id          = UUID()
    var subject     : String
    var date        : Date
    var examTime    : Date?      = nil   // nil = all-day, set = specific hour
    var location    : String     = ""   // e.g. "Hall B, Room 201"
    var notes       : String     = ""
    var calendarEventID: String  = ""   // Google Calendar event ID for updates
    var remindersSent: [Int]     = []   // days-before values already notified

    var daysUntil: Double { date.timeIntervalSinceNow / 86400 }
    var isUrgent : Bool   { daysUntil > 0 && daysUntil <= 7 }
    var pillText : String {
        let d = Int(daysUntil)
        if d < 0  { return "" }
        if d == 0 { return "Today!" }
        return "\(d)d"
    }
}

// ── Weekly Study Goal ─────────────────────────────────────────────────────────

struct SubjectWeeklyGoal: Codable, Identifiable, Equatable {
    var id          = UUID()
    var subject     : String
    var weeklyHours : Double   // planned
}

// ── Heatmap Day ───────────────────────────────────────────────────────────────

struct HeatmapDay: Identifiable {
    var id     = UUID()
    var date   : Date
    var hours  : Double
    var subject: String?
}

// ── Subject Meta (color + Telegram) ──────────────────────────────────────────

struct SubjectMeta: Codable, Identifiable, Equatable {
    var id              = UUID()
    var name            : String
    var colorIndex      : Int    = 0
    var telegramBotToken: String = ""   // per-subject override (rarely needed)
    var telegramChatID  : String = ""   // per-subject override
    var telegramTopicID : Int    = 0    // Forum topic thread ID (0 = main chat, no topic)
}

// ── Daily Goal Mode ───────────────────────────────────────────────────────────

enum DailyGoalMode: String, Codable, CaseIterable {
    case global    = "Global"
    case perSubject = "Per Subject"
    case both      = "Both"
}

// ── Central Subject Store ─────────────────────────────────────────────────────

@Observable
final class SubjectStore {
    static let shared = SubjectStore()

    // ── Global Telegram config (one bot for ALL subjects) ───────────────────
    var globalTelegramToken : String = ""
    var globalTelegramChatID: String = ""
    var useGlobalTelegram   : Bool   = true   // when true, all subjects share one bot

    // Color + Telegram meta per subject name
    var metas         : [SubjectMeta]       = []
    // Exams
    var exams         : [ExamEntry]         = []
    // Daily goal settings
    var dailyGoalMode         : DailyGoalMode  = .global
    var globalDailyGoalHours  : Double         = 4.0
    var globalWeeklyGoalHours : Double         = 20.0  // new global weekly target
    var subjectDailyGoals     : [String: Double] = [:]
    // Study plan (per-subject weekly — kept for backward compat but UI replaced)
    var weeklyGoals           : [SubjectWeeklyGoal] = []

    // ── Persistence URLs ──────────────────────────────────────────────────────

    private func dir() -> URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var metasURL     : URL { dir().appendingPathComponent("subject_metas.json") }
    private var telegramURL  : URL { dir().appendingPathComponent("telegram_global.json") }
    private var examsURL  : URL { dir().appendingPathComponent("exams.json") }
    private var goalsURL  : URL { dir().appendingPathComponent("goals.json") }
    private var planURL   : URL { dir().appendingPathComponent("weekly_plan.json") }

    init() { load() }

    // ── Color helpers ─────────────────────────────────────────────────────────

    func color(for subject: String) -> Color {
        // Always look up persisted meta first — this is the only stable source
        if let meta = metas.first(where: { $0.name == subject }) {
            return subjectPalette[meta.colorIndex % subjectPalette.count]
        }
        // No meta yet — create one immediately so the color is stable from now on
        ensureMeta(for: subject)
        let idx = metas.first(where: { $0.name == subject })?.colorIndex ?? 0
        return subjectPalette[idx % subjectPalette.count]
    }

    func colorHex(for subject: String) -> String {
        if let meta = metas.first(where: { $0.name == subject }) {
            return subjectPaletteHex[meta.colorIndex % subjectPaletteHex.count]
        }
        ensureMeta(for: subject)
        let idx = metas.first(where: { $0.name == subject })?.colorIndex ?? 0
        return subjectPaletteHex[idx % subjectPaletteHex.count]
    }

    func ensureMeta(for subject: String) {
        guard !subject.isEmpty,
              !metas.contains(where: { $0.name == subject }) else { return }
        // Assign next unused palette index so each new subject gets a unique color
        let usedIndices = Set(metas.map { $0.colorIndex % subjectPalette.count })
        var nextIdx = 0
        for i in 0..<subjectPalette.count {
            if !usedIndices.contains(i) { nextIdx = i; break }
        }
        // All 14 slots used — wrap by position
        if usedIndices.count >= subjectPalette.count {
            nextIdx = metas.count % subjectPalette.count
        }
        metas.append(SubjectMeta(name: subject, colorIndex: nextIdx))
        saveMetas()
    }

    /// Call once at launch to seed persistent metas for every known subject
    func seedAllMetas(subjects: [String]) {
        var changed = false
        for s in subjects where !s.isEmpty {
            if !metas.contains(where: { $0.name == s }) {
                let usedIndices = Set(metas.map { $0.colorIndex % subjectPalette.count })
                var nextIdx = 0
                for i in 0..<subjectPalette.count {
                    if !usedIndices.contains(i) { nextIdx = i; break }
                }
                if usedIndices.count >= subjectPalette.count {
                    nextIdx = metas.count % subjectPalette.count
                }
                metas.append(SubjectMeta(name: s, colorIndex: nextIdx))
                changed = true
            }
        }
        if changed { saveMetas() }
    }

    func updateMeta(_ meta: SubjectMeta) {
        if let i = metas.firstIndex(where: { $0.id == meta.id }) {
            metas[i] = meta; saveMetas()
        }
    }

    // ── Exam helpers ──────────────────────────────────────────────────────────

    func addExam(_ exam: ExamEntry) { exams.append(exam); saveExams() }
    func updateExam(_ exam: ExamEntry) {
        if let i = exams.firstIndex(where: { $0.id == exam.id }) {
            exams[i] = exam; saveExams()
        }
    }
    func deleteExam(_ exam: ExamEntry) { exams.removeAll { $0.id == exam.id }; saveExams() }

    var urgentExam: ExamEntry? {
        exams.filter { $0.isUrgent }.sorted { $0.daysUntil < $1.daysUntil }.first
    }

    func urgentExam(for subject: String) -> ExamEntry? {
        exams.filter { $0.subject == subject && $0.isUrgent }
             .sorted { $0.daysUntil < $1.daysUntil }.first
    }

    // ── Daily goal helpers ────────────────────────────────────────────────────

    func goalHours(for subject: String) -> Double {
        switch dailyGoalMode {
        case .global:     return globalDailyGoalHours
        case .perSubject: return subjectDailyGoals[subject] ?? globalDailyGoalHours
        case .both:       return subjectDailyGoals[subject] ?? globalDailyGoalHours
        }
    }

    func progress(for subject: String, sessions: [StudySession]) -> Double {
        let today = sessions.filter {
            Calendar.current.isDateInToday($0.date) && $0.subject == subject
        }.reduce(0) { $0 + $1.duration }
        let goal = goalHours(for: subject) * 3600
        guard goal > 0 else { return 0 }
        return min(today / goal, 1.0)
    }

    func globalProgress(sessions: [StudySession]) -> Double {
        let today = sessions.filter { Calendar.current.isDateInToday($0.date) }
                            .reduce(0) { $0 + $1.duration }
        let goal  = globalDailyGoalHours * 3600
        guard goal > 0 else { return 0 }
        return min(today / goal, 1.0)
    }

    // ── Weekly plan helpers ───────────────────────────────────────────────────

    func setWeeklyGoal(subject: String, hours: Double) {
        if let i = weeklyGoals.firstIndex(where: { $0.subject == subject }) {
            weeklyGoals[i].weeklyHours = hours
        } else {
            weeklyGoals.append(SubjectWeeklyGoal(subject: subject, weeklyHours: hours))
        }
        savePlan()
    }

    func actualHoursThisWeek(subject: String, sessions: [StudySession]) -> Double {
        let cal   = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let secs  = sessions.filter { $0.subject == subject && $0.date >= start }
                             .reduce(0) { $0 + $1.duration }
        return secs / 3600
    }

    func heatmapData(subject: String?, sessions: [StudySession], days: Int = 35) -> [HeatmapDay] {
        var result: [HeatmapDay] = []
        let cal = Calendar.current
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: Date()) else { continue }
            let hours: Double
            if let sub = subject {
                hours = sessions.filter { $0.subject == sub && cal.isDate($0.date, inSameDayAs: date) }
                                 .reduce(0) { $0 + $1.duration } / 3600
            } else {
                hours = sessions.filter { cal.isDate($0.date, inSameDayAs: date) }
                                 .reduce(0) { $0 + $1.duration } / 3600
            }
            result.append(HeatmapDay(date: date, hours: hours, subject: subject))
        }
        return result
    }

    // ── Telegram ──────────────────────────────────────────────────────────────

    func sendToTelegram(subject: String, message: String) {
        let token  : String
        let chatID : String
        let topicID: Int

        let subjectMeta = metas.first { $0.name == subject }

        // Per-subject override takes priority
        if let m = subjectMeta, !m.telegramBotToken.isEmpty, !m.telegramChatID.isEmpty {
            token   = m.telegramBotToken
            chatID  = m.telegramChatID
            topicID = m.telegramTopicID
        } else if !globalTelegramToken.isEmpty && !globalTelegramChatID.isEmpty {
            token   = globalTelegramToken
            chatID  = globalTelegramChatID
            topicID = subjectMeta?.telegramTopicID ?? 0
        } else { return }

        // If message already has HTML formatting (session save), use as-is; otherwise prefix with subject tag
        let text = message.hasPrefix("📖") || message.hasPrefix("📚 [") ? message : "📚 [\(subject)] \(message)"
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/sendMessage")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "chat_id", value: chatID),
            URLQueryItem(name: "text",    value: text),
            URLQueryItem(name: "parse_mode", value: "HTML")
        ]
        if topicID > 0 {
            items.append(URLQueryItem(name: "message_thread_id", value: "\(topicID)"))
        }
        components.queryItems = items
        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { _, _, _ in }.resume()
    }

    // ── Send photo to Telegram ────────────────────────────────────────────────

    func sendPhotoToTelegram(subject: String, image: NSImage, caption: String) {
        let token : String
        let chatID: String
        let topicID: Int
        let meta = metas.first { $0.name == subject }
        if let m = meta, !m.telegramBotToken.isEmpty, !m.telegramChatID.isEmpty {
            token = m.telegramBotToken; chatID = m.telegramChatID; topicID = m.telegramTopicID
        } else if !globalTelegramToken.isEmpty && !globalTelegramChatID.isEmpty {
            token = globalTelegramToken; chatID = globalTelegramChatID
            topicID = meta?.telegramTopicID ?? 0
        } else { return }

        // Convert NSImage → PNG data
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let png  = rep.representation(using: .png, properties: [:])
        else { return }

        // Build multipart/form-data
        let boundary = "StudyNotch-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ val: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(val.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        field("chat_id", chatID)
        if !caption.isEmpty { field("caption", caption) }
        if topicID > 0 { field("message_thread_id", "\(topicID)") }
        field("parse_mode", "HTML")
        // Photo file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"note.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(png)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendPhoto") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // ── Telegram API helpers ──────────────────────────────────────────────────

    /// Fetch the first chat the bot has received a message from (getUpdates)
    func fetchChatID(token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?limit=10&allowed_updates=[%22message%22]") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok   = json["ok"] as? Bool, ok,
                  let results = json["result"] as? [[String: Any]],
                  let first   = results.last,   // most recent message
                  let message = first["message"] as? [String: Any],
                  let chat    = message["chat"] as? [String: Any],
                  let id      = chat["id"]
            else { DispatchQueue.main.async { completion(nil) }; return }
            let chatStr = "\(id)"
            DispatchQueue.main.async { completion(chatStr) }
        }.resume()
    }

    /// Create a forum topic in a supergroup, returns topic thread ID
    /// Create a forum topic. completion(threadID, errorDescription)
    func createForumTopic(token: String, chatID: String, name: String,
                          completion: @escaping (Int?, String?) -> Void) {
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/createForumTopic")!
        components.queryItems = [
            URLQueryItem(name: "chat_id", value: chatID),
            URLQueryItem(name: "name",    value: name)
        ]
        guard let url = components.url else { completion(nil, "Bad URL"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { data, _, networkErr in
            if let e = networkErr {
                DispatchQueue.main.async { completion(nil, e.localizedDescription) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { DispatchQueue.main.async { completion(nil, "No response") }; return }

            if let ok = json["ok"] as? Bool, ok,
               let result = json["result"] as? [String: Any],
               let tid = result["message_thread_id"] as? Int {
                DispatchQueue.main.async { completion(tid, nil) }
            } else {
                let desc = json["description"] as? String ?? "Unknown error"
                let code = json["error_code"] as? Int ?? 0
                DispatchQueue.main.async { completion(nil, "[\(code)] \(desc)") }
            }
        }.resume()
    }

    /// Check if a chat is a supergroup with forum/topics enabled
    func checkGroupRequirements(token: String, chatID: String,
                                completion: @escaping (_ isSupergroup: Bool,
                                                       _ isForum: Bool,
                                                       _ botIsAdmin: Bool,
                                                       _ canManageTopics: Bool,
                                                       _ error: String?,
                                                       _ rawChat: String,
                                                       _ rawAdmins: String) -> Void) {
        // 1. getChat — fetch full group info
        guard let chatURL = URL(string: "https://api.telegram.org/bot\(token)/getChat?chat_id=\(chatID)") else {
            completion(false, false, false, false, "Bad URL", "", ""); return
        }
        URLSession.shared.dataTask(with: chatURL) { data, _, err in
            guard let data = data else {
                let msg = err?.localizedDescription ?? "No data from getChat"
                DispatchQueue.main.async { completion(false, false, false, false, msg, "", "") }
                return
            }
            // Always capture raw response for debugging
            let rawChat = String(data: data, encoding: .utf8) ?? "unreadable"

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false, false, false, false, "JSON parse failed", rawChat, "") }
                return
            }
            guard let ok = json["ok"] as? Bool, ok,
                  let result = json["result"] as? [String: Any] else {
                let desc = json["description"] as? String ?? "getChat returned ok=false"
                DispatchQueue.main.async { completion(false, false, false, false, desc, rawChat, "") }
                return
            }

            let chatType     = result["type"] as? String ?? ""
            let isSupergroup = chatType == "supergroup"
            // is_forum may be absent (false) or true
            let isForum      = result["is_forum"] as? Bool ?? false

            // 2. getChatAdministrators
            guard let adminURL = URL(string: "https://api.telegram.org/bot\(token)/getChatAdministrators?chat_id=\(chatID)") else {
                DispatchQueue.main.async { completion(isSupergroup, isForum, false, false, nil, rawChat, "") }
                return
            }
            URLSession.shared.dataTask(with: adminURL) { data2, _, err2 in
                guard let data2 = data2 else {
                    let msg = err2?.localizedDescription ?? "No data from getChatAdministrators"
                    DispatchQueue.main.async { completion(isSupergroup, isForum, false, false, msg, rawChat, "") }
                    return
                }
                let rawAdmins = String(data: data2, encoding: .utf8) ?? "unreadable"

                guard let json2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
                      let ok2 = json2["ok"] as? Bool, ok2,
                      let admins = json2["result"] as? [[String: Any]] else {
                    let desc = (try? JSONSerialization.jsonObject(with: data2) as? [String: Any])?["description"] as? String
                    DispatchQueue.main.async { completion(isSupergroup, isForum, false, false,
                                                          desc ?? "getChatAdministrators failed",
                                                          rawChat, rawAdmins) }
                    return
                }

                // Find the bot — match by checking is_bot flag
                // can_manage_topics: absent = false in older API, true/false in newer
                var botIsAdmin = false
                var canManageTopics = false
                for admin in admins {
                    guard let user = admin["user"] as? [String: Any],
                          user["is_bot"] as? Bool == true else { continue }
                    botIsAdmin = true
                    // Key may be absent if permission was never explicitly set
                    // Treat absent as false — user needs to explicitly enable it
                    canManageTopics = admin["can_manage_topics"] as? Bool ?? false
                    break
                }

                DispatchQueue.main.async {
                    completion(isSupergroup, isForum, botIsAdmin, canManageTopics,
                               nil, rawChat, rawAdmins)
                }
            }.resume()
        }.resume()
    }



    /// Save a topic ID for a subject
    func setTopicID(_ topicID: Int, for subject: String) {
        if let i = metas.firstIndex(where: { $0.name == subject }) {
            metas[i].telegramTopicID = topicID
            saveMetas()
        }
    }

    /// Returns true if this subject has Telegram configured (global or per-subject)
    func hasTelegram(for subject: String) -> Bool {
        if useGlobalTelegram && !globalTelegramToken.isEmpty && !globalTelegramChatID.isEmpty { return true }
        let meta = metas.first { $0.name == subject }
        return (meta?.telegramBotToken.isEmpty == false) && (meta?.telegramChatID.isEmpty == false)
    }

    func saveGlobalTelegram() {
        let payload: [String: String] = [
            "token": globalTelegramToken,
            "chatID": globalTelegramChatID,
            "useGlobal": useGlobalTelegram ? "1" : "0"
        ]
        try? JSONEncoder().encode(payload).write(to: telegramURL, options: .atomic)
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    func saveMetas() {
        try? JSONEncoder().encode(metas).write(to: metasURL, options: .atomic)
    }
    private func saveExams() {
        try? JSONEncoder().encode(exams).write(to: examsURL, options: .atomic)
    }
    private func savePlan() {
        try? JSONEncoder().encode(weeklyGoals).write(to: planURL, options: .atomic)
    }
    func saveGoals() {
        let payload = GoalsPayload(mode: dailyGoalMode,
                                   global: globalDailyGoalHours,
                                   globalWeekly: globalWeeklyGoalHours,
                                   perSubject: subjectDailyGoals)
        try? JSONEncoder().encode(payload).write(to: goalsURL, options: .atomic)
    }

    private func load() {
        if let d = try? Data(contentsOf: metasURL),
           let v = try? JSONDecoder().decode([SubjectMeta].self, from: d) { metas = v }
        if let d = try? Data(contentsOf: telegramURL),
           let v = try? JSONDecoder().decode([String: String].self, from: d) {
            globalTelegramToken  = v["token"]  ?? ""
            globalTelegramChatID = v["chatID"] ?? ""
            useGlobalTelegram    = (v["useGlobal"] ?? "1") == "1"
        }
        if let d = try? Data(contentsOf: examsURL),
           let v = try? JSONDecoder().decode([ExamEntry].self, from: d) { exams = v }
        if let d = try? Data(contentsOf: planURL),
           let v = try? JSONDecoder().decode([SubjectWeeklyGoal].self, from: d) { weeklyGoals = v }
        if let d = try? Data(contentsOf: goalsURL),
           let v = try? JSONDecoder().decode(GoalsPayload.self, from: d) {
            dailyGoalMode          = v.mode
            globalDailyGoalHours   = v.global
            globalWeeklyGoalHours  = v.globalWeekly ?? 20.0
            subjectDailyGoals      = v.perSubject
        }
    }

    private struct GoalsPayload: Codable {
        var mode         : DailyGoalMode
        var global       : Double
        var globalWeekly : Double?         // optional for backward compat
        var perSubject   : [String: Double]
    }
}
