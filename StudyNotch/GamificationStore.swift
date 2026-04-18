import Foundation
import Observation
import AppKit

// ── XP & Levels ───────────────────────────────────────────────────────────────

struct Level {
    let number : Int
    let title  : String
    let minXP  : Int
    let color  : String   // for display
}

let LEVELS: [Level] = [
    Level(number:1,  title:"Freshman",        minXP:0,     color:"gray"),
    Level(number:2,  title:"Sophomore",        minXP:200,   color:"blue"),
    Level(number:3,  title:"Junior",           minXP:600,   color:"green"),
    Level(number:4,  title:"Senior",           minXP:1200,  color:"orange"),
    Level(number:5,  title:"Honor Student",    minXP:2200,  color:"purple"),
    Level(number:6,  title:"Dean's List",      minXP:3800,  color:"red"),
    Level(number:7,  title:"Graduate",         minXP:6000,  color:"yellow"),
    Level(number:8,  title:"Professor",        minXP:9000,  color:"pink"),
]

// ── Achievement ───────────────────────────────────────────────────────────────

struct Achievement: Codable, Identifiable {
    var id          : String     // unique key
    var title       : String
    var description : String
    var icon        : String     // SF Symbol
    var xpReward    : Int
    var unlockedAt  : Date?
    var isUnlocked  : Bool { unlockedAt != nil }
}

// ── Weekly Challenge ──────────────────────────────────────────────────────────

struct WeeklyChallenge: Codable {
    var id          : String
    var title       : String
    var description : String
    var icon        : String
    var xpReward    : Int
    var target      : Int     // numeric goal
    var progress    : Int     // current progress
    var weekStart   : Date
    var completed   : Bool { progress >= target }
}

// ── Store ─────────────────────────────────────────────────────────────────────

@Observable
final class GamificationStore {
    static let shared = GamificationStore()

    var totalXP      : Int = 0
    var achievements : [Achievement] = []
    var challenge    : WeeklyChallenge?
    var newUnlocks   : [Achievement] = []   // for popup notification

    private var fileURL: URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("gamification.json")
    }

    private var backupFileURL: URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        return d.appendingPathComponent("gamification.backup.json")
    }

    init() {
        // Restore XP from UserDefaults immediately so it's never 0 during load
        totalXP = UserDefaults.standard.integer(forKey: "studynotch.totalXP")
        setupAchievements()
        load()
        refreshChallenge()
    }

    // ── Level helpers ─────────────────────────────────────────────────────────

    var allLevels: [Level] { LEVELS }

    var currentLevel: Level {
        LEVELS.last(where: { totalXP >= $0.minXP }) ?? LEVELS[0]
    }

    var nextLevel: Level? {
        LEVELS.first(where: { $0.minXP > totalXP })
    }

    var progressToNext: Double {
        guard let next = nextLevel else { return 1.0 }
        let cur = currentLevel
        let range = next.minXP - cur.minXP
        let done  = totalXP - cur.minXP
        return Double(done) / Double(range)
    }

    var xpToNext: Int {
        (nextLevel?.minXP ?? totalXP) - totalXP
    }

    // ── XP earning ────────────────────────────────────────────────────────────

    func earnXP(_ amount: Int, reason: String) {
        totalXP += amount
        save()
    }

    func deductXP(_ amount: Int, reason: String) {
        totalXP = max(0, totalXP - amount)  // never go below 0
        // Update UserDefaults mirror immediately
        UserDefaults.standard.set(totalXP, forKey: "studynotch.totalXP")
        save()
    }

    /// Calculate the XP that was awarded for a given session (mirrors processSession logic)
    func xpForSession(_ session: StudySession) -> Int {
        var xp = Int(session.duration / 60)   // 1 per minute
        if session.difficulty >= 4 { xp += 15 }
        else if session.difficulty == 3 { xp += 8 }
        if !session.notes.isEmpty { xp += 5 }
        if session.distractions.isEmpty && session.duration > 1800 { xp += 20 }
        if session.duration >= 3600 { xp += 30 }
        return xp
    }

    /// Call after every session save
    func processSession(_ session: StudySession) {
        var xp = 0

        // Base XP: 1 per minute
        xp += Int(session.duration / 60)

        // Difficulty bonus
        if session.difficulty >= 4 { xp += 15 }
        else if session.difficulty == 3 { xp += 8 }

        // Notes bonus
        if !session.notes.isEmpty { xp += 5 }

        // Zero distraction bonus
        if session.distractions.isEmpty && session.duration > 1800 { xp += 20 }

        // Long session bonus
        if session.duration >= 3600 { xp += 30 }

        earnXP(xp, reason: "Session: \(session.subject)")

        // Check achievements
        checkAchievements()

        // Update challenge
        updateChallenge(session)
    }

    // ── Achievements ──────────────────────────────────────────────────────────

    private func setupAchievements() {
        guard achievements.isEmpty else { return }
        achievements = [
            Achievement(id:"first_session",   title:"First Step",          description:"Complete your first study session",               icon:"star.fill",              xpReward:50),
            Achievement(id:"ten_sessions",     title:"Getting Serious",     description:"Complete 10 study sessions",                      icon:"10.circle.fill",         xpReward:100),
            Achievement(id:"fifty_sessions",   title:"Dedicated Scholar",   description:"Complete 50 study sessions",                      icon:"graduationcap.fill",     xpReward:300),
            Achievement(id:"streak_3",         title:"3-Day Streak",        description:"Study 3 days in a row",                           icon:"flame.fill",             xpReward:75),
            Achievement(id:"streak_7",         title:"Week Warrior",        description:"Study 7 days in a row",                           icon:"bolt.fill",              xpReward:200),
            Achievement(id:"streak_30",        title:"Unstoppable",         description:"Study 30 days in a row",                          icon:"crown.fill",             xpReward:500),
            Achievement(id:"hour_session",     title:"Deep Focus",          description:"Complete a 1-hour session",                       icon:"timer",                  xpReward:80),
            Achievement(id:"two_hour_session", title:"Marathon Studier",    description:"Complete a 2-hour session",                       icon:"hourglass.badge.plus",   xpReward:150),
            Achievement(id:"no_distraction",   title:"Laser Focus",         description:"Complete a 30+ min session with zero distractions",icon:"eye.fill",              xpReward:100),
            Achievement(id:"five_subjects",    title:"Well Rounded",        description:"Study 5 different subjects",                      icon:"books.vertical.fill",    xpReward:120),
            Achievement(id:"ten_hours",        title:"10 Hours Club",       description:"Study a total of 10 hours",                       icon:"10.square.fill",         xpReward:150),
            Achievement(id:"fifty_hours",      title:"50 Hours Club",       description:"Study a total of 50 hours",                       icon:"50.circle.fill",         xpReward:400),
            Achievement(id:"early_bird",       title:"Early Bird",          description:"Study before 8 AM",                               icon:"sunrise.fill",           xpReward:60),
            Achievement(id:"night_owl",        title:"Night Owl",           description:"Study after 11 PM",                               icon:"moon.stars.fill",        xpReward:60),
            Achievement(id:"perfect_week",     title:"Perfect Week",        description:"Study every day for a week",                      icon:"checkmark.seal.fill",    xpReward:250),
            Achievement(id:"all_subjects",     title:"Full Curriculum",     description:"Study all your college subjects in one week",      icon:"list.bullet.clipboard",  xpReward:300),
            // Task achievements
            Achievement(id:"first_task",        title:"Task Master",          description:"Complete your first study task",                    icon:"checkmark.circle.fill",  xpReward:25),
            Achievement(id:"ten_tasks",         title:"Getting Things Done",  description:"Complete 10 study tasks",                          icon:"checklist",              xpReward:75),
            Achievement(id:"fifty_tasks",       title:"Productivity Pro",     description:"Complete 50 study tasks",                          icon:"checklist.checked",      xpReward:200),
            Achievement(id:"high_priority",     title:"Clutch Player",        description:"Complete 5 high-priority tasks",                   icon:"exclamationmark.2",      xpReward:100),
            Achievement(id:"no_overdue",        title:"Always On Time",       description:"Complete 10 tasks before their due date",          icon:"clock.badge.checkmark",  xpReward:150),
            Achievement(id:"daily_tasks_3",     title:"Daily Doer",           description:"Complete 3 tasks in one day",                      icon:"star.circle.fill",       xpReward:60),
        ]
    }

    func checkAchievements() {
        let store     = SessionStore.shared
        let sessions  = store.sessions
        let total     = sessions.reduce(0.0) { $0 + $1.duration }
        let streak    = currentStreak()
        let cal       = Calendar.current
        var newOnes: [Achievement] = []

        func unlock(_ id: String) {
            guard let idx = achievements.firstIndex(where: { $0.id == id }),
                  !achievements[idx].isUnlocked else { return }
            achievements[idx].unlockedAt = Date()
            earnXP(achievements[idx].xpReward, reason: "Achievement: \(achievements[idx].title)")
            newOnes.append(achievements[idx])
        }

        if !sessions.isEmpty                           { unlock("first_session")   }
        if sessions.count >= 10                        { unlock("ten_sessions")    }
        if sessions.count >= 50                        { unlock("fifty_sessions")  }
        if streak >= 3                                 { unlock("streak_3")        }
        if streak >= 7                                 { unlock("streak_7")        }
        if streak >= 30                                { unlock("streak_30")       }
        if sessions.contains(where:{$0.duration>=3600}){ unlock("hour_session")   }
        if sessions.contains(where:{$0.duration>=7200}){ unlock("two_hour_session")}
        if sessions.contains(where:{$0.distractions.isEmpty && $0.duration >= 1800}) { unlock("no_distraction") }
        if store.subjectTotals.count >= 5              { unlock("five_subjects")   }
        if total >= 36000                              { unlock("ten_hours")       }
        if total >= 180000                             { unlock("fifty_hours")     }
        if sessions.contains(where:{ cal.component(.hour, from:$0.startTime) < 8 })  { unlock("early_bird") }
        if sessions.contains(where:{ cal.component(.hour, from:$0.startTime) >= 23 }){ unlock("night_owl")  }

        // Perfect week
        let weekDays = (0..<7).map { cal.date(byAdding:.day, value:-$0, to:Date())! }
        if weekDays.allSatisfy({ d in sessions.contains(where:{ cal.isDate($0.date,inSameDayAs:d) }) }) {
            unlock("perfect_week")
        }

        if !newOnes.isEmpty {
            DispatchQueue.main.async { self.newUnlocks = newOnes }
            save()
        }
    }

    // ── Weekly Challenge ──────────────────────────────────────────────────────

    func refreshChallenge() {
        let cal  = Calendar.current
        let now  = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        // If same week and challenge exists, just update progress
        if var c = challenge, cal.isDate(c.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) {
            updateChallengeProgress(&c)
            challenge = c
            return
        }

        // New week — pick a new challenge
        let challenges: [WeeklyChallenge] = [
            WeeklyChallenge(id:"study_5_days",  title:"5-Day Streak",        description:"Study at least once on 5 different days this week",  icon:"calendar.badge.checkmark", xpReward:200, target:5,   progress:0, weekStart:weekStart),
            WeeklyChallenge(id:"5_hours",       title:"5 Hours This Week",    description:"Accumulate 5 hours of study time this week",          icon:"clock.fill",               xpReward:180, target:300, progress:0, weekStart:weekStart),
            WeeklyChallenge(id:"3_subjects",    title:"3 Subjects",           description:"Study at least 3 different subjects this week",       icon:"books.vertical.fill",      xpReward:160, target:3,   progress:0, weekStart:weekStart),
            WeeklyChallenge(id:"no_distractions", title:"Focus Master",         description:"Complete 3 sessions with zero distractions",          icon:"eye.fill",                  xpReward:220, target:3,   progress:0, weekStart:weekStart),
            WeeklyChallenge(id:"long_session",  title:"Deep Work",            description:"Complete one session longer than 90 minutes",         icon:"hourglass",                xpReward:190, target:1,   progress:0, weekStart:weekStart),
        ]
        var picked = challenges[abs(weekStart.hashValue) % challenges.count]
        updateChallengeProgress(&picked)
        challenge = picked
        save()
    }

    private func updateChallengeProgress(_ c: inout WeeklyChallenge) {
        let cal      = Calendar.current
        let weekSessions = SessionStore.shared.sessions.filter {
            cal.isDate($0.date, equalTo: c.weekStart, toGranularity: .weekOfYear)
        }
        switch c.id {
        case "study_5_days":
            c.progress = Set(weekSessions.map { cal.startOfDay(for:$0.date) }).count
        case "5_hours":
            c.progress = Int(weekSessions.reduce(0){$0+$1.duration} / 60)
        case "3_subjects":
            c.progress = Set(weekSessions.map(\.subject)).count
        case "no_distractions":
            c.progress = weekSessions.filter { $0.distractions.isEmpty && $0.duration > 600 }.count
        case "long_session":
            c.progress = weekSessions.contains(where:{$0.duration >= 5400}) ? 1 : 0
        default: break
        }
    }

    private func updateChallenge(_ session: StudySession) {
        guard var c = challenge else { return }
        updateChallengeProgress(&c)
        if c.completed && !(challenge?.completed ?? false) {
            earnXP(c.xpReward, reason: "Challenge: \(c.title)")
        }
        challenge = c
        save()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func currentStreak() -> Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while SessionStore.shared.sessions.contains(where:{cal.isDate($0.date,inSameDayAs:day)}) {
            n += 1; day = cal.date(byAdding:.day, value:-1, to:day)!
        }
        return n
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private struct SaveData: Codable {
        var totalXP     : Int
        var achievements: [Achievement]
        var challenge   : WeeklyChallenge?
    }

    func save() {
        // Mirror XP to UserDefaults as instant backup (survives corrupt JSON)
        UserDefaults.standard.set(totalXP, forKey: "studynotch.totalXP")
        let data = SaveData(totalXP: totalXP, achievements: achievements, challenge: challenge)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        // Write to primary and backup so a deleted primary never wipes XP
        try? encoded.write(to: fileURL,       options: .atomic)
        try? encoded.write(to: backupFileURL, options: .atomic)
    }

    private func load() {
        // Try primary first, fall back to backup
        let raw: Data?
        if let d = try? Data(contentsOf: fileURL) {
            raw = d
        } else if let d = try? Data(contentsOf: backupFileURL) {
            raw = d
            // Restore primary from backup
            try? d.write(to: fileURL, options: .atomic)
        } else {
            raw = nil
        }

        guard let raw = raw,
              let data = try? JSONDecoder().decode(SaveData.self, from: raw) else { return }

        // Take the highest XP value from all sources — never go backwards
        let mirrored = UserDefaults.standard.integer(forKey: "studynotch.totalXP")
        totalXP = max(totalXP, data.totalXP, mirrored)
        achievements = data.achievements
        challenge    = data.challenge
        // Merge any new achievements added since last run.
        // IMPORTANT: do NOT create a GamificationStore() here — that causes
        // infinite recursion (load → setupAchievementsDefault → init → load…)
        // and a stack-overflow crash on every launch after the first session.
        for a in GamificationStore.defaultAchievements where !achievements.contains(where: { $0.id == a.id }) {
            achievements.append(a)
        }
    }

    // ── Task achievement checker ─────────────────────────────────────────────

    func checkTaskAchievements() {
        let store     = TaskStore.shared
        let completed = store.tasks.filter { $0.isCompleted }
        let cal       = Calendar.current
        let today     = completed.filter { cal.isDateInToday($0.completedAt ?? .distantPast) }
        let highDone  = completed.filter { $0.priority == .high }.count
        let onTime    = completed.filter {
            guard let due = $0.dueDate, let done = $0.completedAt else { return false }
            return done <= due
        }.count

        func unlock(_ id: String) {
            guard let idx = achievements.firstIndex(where: { $0.id == id }),
                  !achievements[idx].isUnlocked else { return }
            achievements[idx].unlockedAt = Date()
            earnXP(achievements[idx].xpReward, reason: "Achievement: \(achievements[idx].title)")
            newUnlocks.append(achievements[idx])
            save()
        }

        if !completed.isEmpty      { unlock("first_task")    }
        if completed.count >= 10   { unlock("ten_tasks")     }
        if completed.count >= 50   { unlock("fifty_tasks")   }
        if highDone >= 5           { unlock("high_priority") }
        if onTime >= 10            { unlock("no_overdue")    }
        if today.count >= 3        { unlock("daily_tasks_3") }
    }

    // Static so it can be called from load() without instantiating a new store.
    static var defaultAchievements: [Achievement] {
        [
            Achievement(id:"first_session",   title:"First Step",          description:"Complete your first study session",               icon:"star.fill",              xpReward:50),
            Achievement(id:"ten_sessions",     title:"Getting Serious",     description:"Complete 10 study sessions",                      icon:"10.circle.fill",         xpReward:100),
            Achievement(id:"fifty_sessions",   title:"Dedicated Scholar",   description:"Complete 50 study sessions",                      icon:"graduationcap.fill",     xpReward:300),
            Achievement(id:"streak_3",         title:"3-Day Streak",        description:"Study 3 days in a row",                           icon:"flame.fill",             xpReward:75),
            Achievement(id:"streak_7",         title:"Week Warrior",        description:"Study 7 days in a row",                           icon:"bolt.fill",              xpReward:200),
            Achievement(id:"streak_30",        title:"Unstoppable",         description:"Study 30 days in a row",                          icon:"crown.fill",             xpReward:500),
            Achievement(id:"hour_session",     title:"Deep Focus",          description:"Complete a 1-hour session",                       icon:"timer",                  xpReward:80),
            Achievement(id:"two_hour_session", title:"Marathon Studier",    description:"Complete a 2-hour session",                       icon:"hourglass.badge.plus",   xpReward:150),
            Achievement(id:"no_distraction",   title:"Laser Focus",         description:"Complete a 30+ min session with zero distractions",icon:"eye.fill",              xpReward:100),
            Achievement(id:"five_subjects",    title:"Well Rounded",        description:"Study 5 different subjects",                      icon:"books.vertical.fill",    xpReward:120),
            Achievement(id:"ten_hours",        title:"10 Hours Club",       description:"Study a total of 10 hours",                       icon:"10.square.fill",         xpReward:150),
            Achievement(id:"fifty_hours",      title:"50 Hours Club",       description:"Study a total of 50 hours",                       icon:"50.circle.fill",         xpReward:400),
            Achievement(id:"early_bird",       title:"Early Bird",          description:"Study before 8 AM",                               icon:"sunrise.fill",           xpReward:60),
            Achievement(id:"night_owl",        title:"Night Owl",           description:"Study after 11 PM",                               icon:"moon.stars.fill",        xpReward:60),
            Achievement(id:"perfect_week",     title:"Perfect Week",        description:"Study every day for a week",                      icon:"checkmark.seal.fill",    xpReward:250),
            Achievement(id:"all_subjects",     title:"Full Curriculum",     description:"Study all your college subjects in one week",      icon:"list.bullet.clipboard",  xpReward:300),
            Achievement(id:"first_task",        title:"Task Master",          description:"Complete your first study task",                    icon:"checkmark.circle.fill",  xpReward:25),
            Achievement(id:"ten_tasks",         title:"Getting Things Done",  description:"Complete 10 study tasks",                          icon:"checklist",              xpReward:75),
            Achievement(id:"fifty_tasks",       title:"Productivity Pro",     description:"Complete 50 study tasks",                          icon:"checklist.checked",      xpReward:200),
            Achievement(id:"high_priority",     title:"Clutch Player",        description:"Complete 5 high-priority tasks",                   icon:"exclamationmark.2",      xpReward:100),
            Achievement(id:"no_overdue",        title:"Always On Time",       description:"Complete 10 tasks before their due date",          icon:"clock.badge.checkmark",  xpReward:150),
            Achievement(id:"daily_tasks_3",     title:"Daily Doer",           description:"Complete 3 tasks in one day",                      icon:"star.circle.fill",       xpReward:60),
        ]
    }
}
