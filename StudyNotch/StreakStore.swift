import Foundation
import SwiftUI
import Observation

// ── StreakStore ────────────────────────────────────────────────────────────────
//
//  Tracks:
//    • Current study streak (consecutive days with ≥ 1 session)
//    • Longest streak ever
//    • Daily completion grid (last 12 weeks) — GitHub-style
//    • Streak freeze: user can protect 1 day per week from breaking the streak
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class StreakStore {
    static let shared = StreakStore()

    // ── Observable state ─────────────────────────────────────────────────────
    private(set) var currentStreak  : Int    = 0
    private(set) var longestStreak  : Int    = 0
    private(set) var totalStudyDays : Int    = 0
    private(set) var studiedDates   : Set<String> = []  // "yyyy-MM-dd"
    private(set) var frozenDates    : Set<String> = []  // protected days

    // Freeze budget: 1 per week
    var freezesUsedThisWeek: Int {
        let cal = Calendar.current
        return frozenDates.filter { key in
            guard let d = Self.date(from: key) else { return false }
            return cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
        }.count
    }
    var canFreeze: Bool { freezesUsedThisWeek < 1 }

    // ── Grid data — 12 weeks × 7 days ─────────────────────────────────────────
    struct GridDay: Identifiable {
        let id       = UUID()
        let date     : Date
        let key      : String    // "yyyy-MM-dd"
        let studied  : Bool
        let frozen   : Bool
        let isToday  : Bool
        let hours    : Double    // hours studied that day
    }

    var gridDays: [GridDay] {
        let cal  = Calendar.current
        let fmt  = Self.keyFormatter
        // Go back 83 days (12 weeks - 1 day) from today, aligned to start of week
        let today     = cal.startOfDay(for: Date())
        let startOffset = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        let gridStart = cal.date(byAdding: .day, value: -(83 + startOffset), to: today)!

        return (0..<(84 + startOffset)).map { offset in
            let d   = cal.date(byAdding: .day, value: offset, to: gridStart)!
            let key = fmt.string(from: d)
            let hrs = sessionHours[key] ?? 0
            return GridDay(
                date   : d,
                key    : key,
                studied: studiedDates.contains(key),
                frozen : frozenDates.contains(key),
                isToday: cal.isDateInToday(d),
                hours  : hrs
            )
        }.filter { !Calendar.current.isDate($0.date, inSameDayAs: Date()) || $0.isToday }
    }

    // Hours studied per day (for intensity shading)
    private var sessionHours: [String: Double] = [:]

    // ── Persistence ───────────────────────────────────────────────────────────

    private var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("streak.json")
    }

    private struct Payload: Codable {
        var studiedDates : [String]
        var frozenDates  : [String]
        var longestStreak: Int
    }

    init() {
        load()
        rebuild()
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /// Call after a session is saved to refresh streak
    func rebuild() {
        let cal  = Calendar.current
        let fmt  = Self.keyFormatter
        let sessions = SessionStore.shared.sessions

        // Build studied-dates set + hours map
        var dates = Set<String>()
        var hours = [String: Double]()
        for s in sessions {
            let key = fmt.string(from: s.startTime)
            dates.insert(key)
            hours[key, default: 0] += s.duration / 3600
        }
        studiedDates  = dates
        sessionHours  = hours
        totalStudyDays = dates.count

        // Compute current streak (going back from today)
        var streak = 0
        var day    = cal.startOfDay(for: Date())
        while true {
            let key = fmt.string(from: day)
            if dates.contains(key) || frozenDates.contains(key) {
                streak += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else {
                break
            }
        }
        currentStreak = streak
        longestStreak = max(longestStreak, streak)

        save()
    }

    /// Freeze today to protect streak
    func freezeToday() {
        guard canFreeze else { return }
        let key = Self.keyFormatter.string(from: Date())
        frozenDates.insert(key)
        rebuild()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    static var keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func date(from key: String) -> Date? {
        keyFormatter.date(from: key)
    }

    func intensityColor(for hours: Double) -> Color {
        let accent = Color(red: 0.2, green: 1.0, blue: 0.55)
        if hours <= 0    { return Color.white.opacity(0.06) }
        if hours < 0.5   { return accent.opacity(0.25) }
        if hours < 1.5   { return accent.opacity(0.45) }
        if hours < 3.0   { return accent.opacity(0.65) }
        return accent.opacity(0.90)
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func save() {
        let p = Payload(studiedDates: Array(studiedDates),
                        frozenDates:  Array(frozenDates),
                        longestStreak: longestStreak)
        try? JSONEncoder().encode(p).write(to: url, options: .atomic)
    }

    private func load() {
        guard let d = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(Payload.self, from: d) else { return }
        studiedDates  = Set(p.studiedDates)
        frozenDates   = Set(p.frozenDates)
        longestStreak = p.longestStreak
    }
}

// ── Streak Heatmap View ───────────────────────────────────────────────────────

struct StreakHeatmapView: View {
    @Bindable var store = StreakStore.shared
    @State private var hoveredKey: String? = nil

    private let columns = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7)
    private let accent   = Color(red: 0.2, green: 1.0, blue: 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Day labels
            HStack(spacing: 3) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d).font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 11, alignment: .center)
                }
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(store.gridDays) { day in
                    let color = day.frozen
                        ? Color.blue.opacity(0.5)
                        : store.intensityColor(for: day.hours)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(color)
                        .frame(width: 11, height: 11)
                        .overlay(
                            day.isToday
                            ? RoundedRectangle(cornerRadius: 2.5)
                                .stroke(accent, lineWidth: 1.5)
                            : nil
                        )
                        .onHover { h in hoveredKey = h ? day.key : nil }
                        .help(tooltipText(for: day))
                }
            }

            // Hovered day detail
            if let key = hoveredKey,
               let day = store.gridDays.first(where: { $0.key == key }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.intensityColor(for: day.hours))
                        .frame(width: 6, height: 6)
                    Text(tooltipText(for: day))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    func tooltipText(for day: StreakStore.GridDay) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let dateStr = df.string(from: day.date)
        if day.frozen  { return "\(dateStr) — Streak frozen ❄️" }
        if day.hours > 0 { return "\(dateStr) — \(String(format:"%.1f",day.hours))h studied" }
        return "\(dateStr) — No study"
    }
}
