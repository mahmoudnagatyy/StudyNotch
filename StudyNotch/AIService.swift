import Foundation
import Observation

// ── AI Service — Groq API (completely free, no credit card) ───────────────────
// Model: llama-3.3-70b-versatile — powerful, fast, free
// Get your free key at: console.groq.com (sign up, no billing needed)
// Free limits: 30 req/min, 14,400 req/day — more than enough

@Observable
final class AIService {
    static let shared = AIService()

     var scheduleResult       : String = ""
     var reportResult         : String = ""
     var courseAnalysisResult : String = ""
     var styleResult          : String = ""
     var isLoadingSchedule       = false
     var isLoadingReport         = false
     var isLoadingCourseAnalysis = false
     var isLoadingStyle          = false

    private let endpoint = "https://api.groq.com/openai/v1/chat/completions"
    var selectedModel: String = "llama-3.3-70b-versatile"
    private var model: String { selectedModel }

    // ── Smart Schedule ────────────────────────────────────────────────────────

    func generateSchedule() {
        guard !isLoadingSchedule else { return }
        let store = SessionStore.shared
        isLoadingSchedule = true; scheduleResult = ""

        let prompt = """
        You are a study coach building a personalised 3-day schedule.
        If the user asks you to remember something, emit it on a new line as: MEMORY: <fact>

        Here is the COMPLETE picture of this student's situation — subjects they study, \
        subjects they haven't touched yet, all pending tasks, exam deadlines, and weekly goals:

        \(store.fullContextForAI)

        IMPORTANT RULES:
        - Subjects marked "⚠️ NOT STUDIED YET" need attention — include them in the plan if they have an exam or task.
        - Tasks that are overdue or due soon MUST appear in the schedule.
        - Match planned hours to the weekly goal targets where possible.
        - Prioritise subjects with exams in ≤ 7 days.
        - Be specific: name the subject, the task (if relevant), the duration, and the best time of day.

        Give me:
        1. A concrete day-by-day schedule for the next 3 days (Day 1 / Day 2 / Day 3, with subjects + durations)
        2. Top priority subject and why
        3. One actionable tip based on their patterns

        Format with bullet points. Max 250 words. Be direct — no fluff.
        """
        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async { self?.scheduleResult = result; self?.isLoadingSchedule = false }
        }
    }

    // ── Weekly Report ─────────────────────────────────────────────────────────

    func generateWeeklyReport() {
        guard !isLoadingReport else { return }
        isLoadingReport = true; reportResult = ""

        let store     = SessionStore.shared
        let cutoff    = Date().addingTimeInterval(-7 * 86400)
        let weekly    = store.sessions.filter { $0.startTime > cutoff }
        let totalMins = Int(weekly.reduce(0) { $0 + $1.duration } / 60)

        let prompt = """
        You are a study coach writing a weekly performance review.

        Full student context (subjects, tasks, exams, goals, and session history):
        \(store.fullContextForAI)

        This week specifically: \(weekly.count) sessions, \(totalMins) minutes studied.

        IMPORTANT: Comment on subjects that appear in the subject list but have ZERO \
        sessions this week — they are gaps that need addressing. Also reference any \
        overdue or upcoming tasks. Compare actual hours to the weekly goals.

        Write:
        1. Headline summary (one sentence)
        2. What went well this week
        3. Gaps and warnings (unstudied subjects, overdue tasks, approaching exams)
        4. One specific goal for next week

        Max 220 words. Be honest — don't sugarcoat gaps.
        """
        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async { self?.reportResult = result; self?.isLoadingReport = false }
        }
    }

    // ── Study Style Detector ──────────────────────────────────────────────────

    func detectStudyStyle() {
        guard !isLoadingStyle else { return }
        let store = SessionStore.shared
        guard store.sessions.count >= 3 else {
            styleResult = "You need at least 3 sessions before I can detect your study style. Keep going!"
            return
        }
        isLoadingStyle = true; styleResult = ""

        let prompt = """
        You are a learning scientist analysing a student's study patterns.

        Session data (subject | day | time | duration | difficulty | distractions):
        \(store.styleDataForAI)

        Pending tasks they haven't finished yet:
        \(TaskStore.shared.tasks.filter { !$0.isCompleted }.prefix(10)
            .map { "• \($0.title) [\($0.subject)] \($0.taskType.rawValue)" }
            .joined(separator: "\n").isEmpty
          ? "(none)"
          : TaskStore.shared.tasks.filter { !$0.isCompleted }.prefix(10)
            .map { "• \($0.title) [\($0.subject)] \($0.taskType.rawValue)" }
            .joined(separator: "\n"))

        Write a Study Style Profile covering:
        - Best study time and optimal session length
        - Distraction patterns and how to address them
        - Subject rhythm (do they avoid certain subjects?)
        - Task completion behaviour
        - One headline sentence capturing their study personality

        Be specific — reference the data. Max 220 words.
        """
        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async { self?.styleResult = result; self?.isLoadingStyle = false }
        }
    }

    // ── Personal Course Analysis ──────────────────────────────────────────────

    func analyzePersonalCourses() {
        guard !isLoadingCourseAnalysis else { return }
        let modeStore = ModeStore.shared
        guard !modeStore.personalCourses.isEmpty else {
            courseAnalysisResult = "Add some personal courses first!"; return
        }
        isLoadingCourseAnalysis = true; courseAnalysisResult = ""
        let sessionsSummary = SessionStore.shared.sessions
            .filter { $0.mode == StudyMode.personal.rawValue }.prefix(20)
            .map { "\($0.subject) — \(Int($0.duration/60))min" }.joined(separator: ", ")
        let prompt = """
        You are a learning coach who helps people finish what they start.
        Courses: \(modeStore.personalCourseSummaryForAI)
        Recent sessions: \(sessionsSummary.isEmpty ? "none yet" : sessionsSummary)
        Analyse honestly: are they spreading too thin? Which to finish? Which to skip? One clear recommendation.
        Be direct, not just encouraging. Max 200 words.
        """
        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async { self?.courseAnalysisResult = result; self?.isLoadingCourseAnalysis = false }
        }
    }

    // ── Multi-turn Chat ────────────────────────────────────────────────────────
    //
    //  Sends the full conversation history so the model has context across turns.
    //  The system prompt includes live study data + pinned memory.
    //  When the user says "remember that X", the AI emits "MEMORY: X" on its own
    //  line — AIChatStore detects and persists this automatically.

    func chat(history: [ChatMessage], systemPrompt: String,
              completion: @escaping (String) -> Void) {
        let key = apiKey()
        guard !key.isEmpty else {
            completion("⚠️ No API key set. Add your free Groq key in Analytics → AI Coach.")
            return
        }
        guard let url = URL(string: endpoint) else { return }

        // Build messages array: system + rolling history
        var msgs: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in history {
            guard msg.role != .system else { continue }
            msgs.append(["role": msg.role.rawValue, "content": msg.content])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)",    forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 45

        let body: [String: Any] = [
            "model"      : model,
            "max_tokens" : 1200,
            "temperature": 0.7,
            "messages"   : msgs
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion("⚠️ \(error.localizedDescription)"); return }
            guard let data = data else { completion("⚠️ No response."); return }
            if let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let text    = message["content"] as? String {
                completion(text); return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err  = json["error"] as? [String: Any],
               let msg  = err["message"] as? String {
                completion("⚠️ Groq error: \(msg)"); return
            }
            completion("⚠️ Unexpected response.")
        }.resume()
    }

    // Groq uses the same format as OpenAI — simple and clean

    private func call(prompt: String, completion: @escaping (String) -> Void) {
        let key = apiKey()
        guard !key.isEmpty else {
            completion("⚠️ No API key — paste your Groq key in AI Coach tab.\nGet it free at console.groq.com")
            return
        }
        guard let url = URL(string: endpoint) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)",       forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model"      : model,
            "max_tokens" : 800,
            "temperature": 0.7,
            "messages"   : [["role": "user", "content": prompt]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion("⚠️ Network error: \(error.localizedDescription)"); return
            }
            guard let data = data else { completion("⚠️ No response."); return }

            // Success — OpenAI-compatible response format
            if let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let text    = message["content"] as? String {
                completion(text); return
            }
            // Error
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err  = json["error"] as? [String: Any],
               let msg  = err["message"] as? String {
                completion("⚠️ Groq error: \(msg)"); return
            }
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            completion("⚠️ Unexpected: \(raw.prefix(200))")
        }.resume()
    }

    func apiKey() -> String {
        UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
    }

    /// Public wrapper for external callers (TodayView, etc.)
    func callPublic(prompt: String, completion: @escaping (String) -> Void) {
        call(prompt: prompt, completion: completion)
    }

    // ── AI Acts: Session Length Insight ──────────────────────────────────────
    //  Analyses session duration vs difficulty to find the user's optimal length.
    //  "You tend to rate sessions >40min as Hard — try 30min sessions."

     var sessionLengthInsight : String = ""
     var isAnalysingLength    = false

    func analyseSessionLength() {
        guard !isAnalysingLength else { return }
        let sessions = SessionStore.shared.sessions
        guard sessions.count >= 5 else {
            sessionLengthInsight = "Need at least 5 sessions to analyse session length patterns."
            return
        }
        isAnalysingLength = true; sessionLengthInsight = ""

        // Build data: duration buckets vs average difficulty
        struct Bucket { var totalDiff: Int; var count: Int; var avgMins: Double }
        var buckets: [String: Bucket] = [
            "< 20m":  .init(totalDiff: 0, count: 0, avgMins: 15),
            "20–35m": .init(totalDiff: 0, count: 0, avgMins: 27),
            "35–50m": .init(totalDiff: 0, count: 0, avgMins: 42),
            "50–70m": .init(totalDiff: 0, count: 0, avgMins: 60),
            "> 70m":  .init(totalDiff: 0, count: 0, avgMins: 85),
        ]
        for s in sessions where s.difficulty > 0 {
            let m = s.duration / 60
            let key: String
            if m < 20 { key = "< 20m" }
            else if m < 35 { key = "20–35m" }
            else if m < 50 { key = "35–50m" }
            else if m < 70 { key = "50–70m" }
            else { key = "> 70m" }
            buckets[key]?.totalDiff += s.difficulty
            buckets[key]?.count += 1
        }
        let summary = buckets.compactMap { key, b -> String? in
            guard b.count > 0 else { return nil }
            let avg = Double(b.totalDiff) / Double(b.count)
            return "\(key): avg difficulty \(String(format:"%.1f",avg))/5 (\(b.count) sessions)"
        }.joined(separator: "\n")

        let prompt = """
        You are a study scientist analysing a student's session length vs difficulty data.

        Data (duration bucket → average difficulty rating, where 1=Hard 5=Easy):
        \(summary)

        Recent session notes for context:
        \(SessionStore.shared.sessions.prefix(10).map { "\(Int($0.duration/60))min \($0.subject) diff=\($0.difficulty)" }.joined(separator: ", "))

        Give ONE specific, actionable recommendation about optimal session length.
        Be direct and data-driven. Example: "Your 35-50 min sessions have your best ratings — stick to that window. Sessions over 70 min average Hard (2.1/5), suggesting fatigue sets in."
        Max 60 words. No bullet points. No fluff.
        """
        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                self?.sessionLengthInsight = result
                self?.isAnalysingLength = false
            }
        }
    }

    // ── AI Acts: auto-adjust weekly plan ──────────────────────────────────────
    //
    //  Analyses current load vs goals and returns concrete JSON adjustments
    //  that the app can apply directly to weekly goals

     var planAdjustResult  : String = ""
     var isAdjustingPlan   = false

    func autoAdjustPlan(completion: @escaping ([(subject: String, newHours: Double, reason: String)]) -> Void) {
        guard !isAdjustingPlan else { return }
        isAdjustingPlan = true

        let store    = SessionStore.shared
        let subStore = SubjectStore.shared
        let tasks    = TaskStore.shared

        // Build context
        var ctx = "WEEKLY GOALS vs ACTUAL:\n"
        for goal in subStore.weeklyGoals {
            let actual = subStore.actualHoursThisWeek(subject: goal.subject, sessions: store.sessions)
            let pct    = goal.weeklyHours > 0 ? Int(actual / goal.weeklyHours * 100) : 0
            ctx += "  \(goal.subject): goal=\(String(format:"%.0f",goal.weeklyHours))h actual=\(String(format:"%.1f",actual))h (\(pct)%)\n"
        }
        ctx += "\nOVERDUE TASKS: \(tasks.tasks.filter { $0.isOverdue }.count)\n"
        ctx += "\nEXAMS THIS WEEK:\n"
        for exam in subStore.exams.filter({ $0.daysUntil > 0 && $0.daysUntil <= 7 }) {
            ctx += "  \(exam.subject) in \(Int(exam.daysUntil)) days\n"
        }
        ctx += "\n" + store.summaryForAI

        let prompt = """
        You are an AI study planner that makes DECISIONS, not suggestions.
        Here is the student's current situation:
        \(ctx)

        Respond ONLY with valid JSON — no explanation, no markdown:
        [
          {"subject": "Physics", "newHours": 8, "reason": "Exam in 3 days"},
          {"subject": "Math", "newHours": 4, "reason": "Already at 80% — reduce to avoid overload"},
          ...
        ]

        Rules:
        - Only include subjects that need adjustment (skip ones that are on track)
        - Max 3 adjustments
        - Reasons must be specific (mention actual data: hours, %, exam dates)
        - newHours must be realistic (between 2 and 15)
        - If someone is overloaded overall, reduce the lowest-priority subject
        """

        call(prompt: prompt) { [weak self] result in
            DispatchQueue.main.async { self?.isAdjustingPlan = false }
            // Parse JSON
            var cleanResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanResult.hasPrefix("```") {
                cleanResult = cleanResult.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
                if cleanResult.hasSuffix("```") { cleanResult = String(cleanResult.dropLast(3)) }
            }
            guard let data = cleanResult.data(using: .utf8),
                  let arr  = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                DispatchQueue.main.async {
                    self?.planAdjustResult = "Could not parse AI response. Raw: \(result.prefix(200))"
                    completion([])
                }
                return
            }
            let adjustments = arr.compactMap { d -> (String, Double, String)? in
                guard let subject  = d["subject"]  as? String,
                      let newHours = d["newHours"]  as? Double,
                      let reason   = d["reason"]    as? String
                else { return nil }
                return (subject, newHours, reason)
            }
            DispatchQueue.main.async {
                self?.planAdjustResult = adjustments.map { "\($0.0): \($0.1)h — \($0.2)" }.joined(separator: "\n")
                completion(adjustments)
            }
        }
    }

    func saveKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "groq_api_key")
    }
}
