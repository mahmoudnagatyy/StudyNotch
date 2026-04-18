import SwiftUI
import AppKit
import Charts

// ── Progress View ─────────────────────────────────────────────────────────────
//  Tab 2 in the new 4-tab structure.
//  Sections: Overview → Sessions → Insights → Gamification
//  No nested tab bar — pure scroll.

struct ProgressTabView: View {
    enum SessionTimeFilter: String, CaseIterable, Identifiable {
        case allTime = "All Time"
        case today = "Today"
        case last7Days = "Last 7 Days"
        case last30Days = "Last 30 Days"

        var id: String { rawValue }
    }

    enum SessionDurationFilter: String, CaseIterable, Identifiable {
        case all = "Any Length"
        case short = "Under 30m"
        case medium = "30m to 90m"
        case long = "Over 90m"

        var id: String { rawValue }
    }

    struct SubjectSessionSummary {
        let subject: String
        let totalTime: TimeInterval
        let filteredTime: TimeInterval
        let sessionCount: Int
        let notesCount: Int
        let highlights: [String]
    }

    var store    = SessionStore.shared
    @Bindable var subStore = SubjectStore.shared
    var gStore   = GamificationStore.shared
    @Bindable var modeStore = ModeStore.shared
    private let allSubjectsToken = "__all_subjects__"

    @State private var editingSession  : StudySession? = nil
    @State private var animateIn       = false
    @State private var animateChart    = false
    @State private var expandedSection : Set<String> = ["overview", "sessions", "insights", "xp"]
    @State private var selectedDay     : String? = nil     // bar chart drill-down
    @State private var selectedHour    : Int?    = nil     // heatmap drill-down
    @State private var showWeeklyDetail: Bool    = false   // weekly ring drill-down
    @State private var subjectFilter: String = "__all_subjects__"
    @State private var timeFilter: SessionTimeFilter = .allTime
    @State private var durationFilter: SessionDurationFilter = .all

    var isCollege: Bool { modeStore.currentMode == .college }

    var modeSessions: [StudySession] {
        sortSessions(store.sessions.filter { $0.mode == modeStore.currentMode.rawValue })
    }

    var modeSubjectTotals: [(subject: String, total: TimeInterval)] {
        var map: [String: TimeInterval] = [:]
        modeSessions.forEach { map[$0.subject, default: 0] += $0.duration }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var availableSubjects: [String] {
        modeSubjectTotals.map(\.subject)
    }

    var hasActiveSessionFilters: Bool {
        subjectFilter != allSubjectsToken || timeFilter != .allTime || durationFilter != .all
    }

    var filteredSessions: [StudySession] {
        let cal = Calendar.current
        let now = Date()
        return modeSessions.filter { session in
            let subjectOk: Bool
            if subjectFilter == allSubjectsToken {
                subjectOk = true
            } else {
                subjectOk = normalizeSubject(session.subject) == normalizeSubject(subjectFilter)
            }

            let timeOk: Bool
            switch timeFilter {
            case .allTime:
                timeOk = true
            case .today:
                timeOk = cal.isDateInToday(session.startTime)
            case .last7Days:
                timeOk = session.startTime >= now.addingTimeInterval(-7 * 86400)
            case .last30Days:
                timeOk = session.startTime >= now.addingTimeInterval(-30 * 86400)
            }

            let mins = session.duration / 60
            let durationOk: Bool
            switch durationFilter {
            case .all:
                durationOk = true
            case .short:
                durationOk = mins < 30
            case .medium:
                durationOk = mins >= 30 && mins <= 90
            case .long:
                durationOk = mins > 90
            }
            return subjectOk && timeOk && durationOk
        }
    }

    var selectedSubjectSummary: SubjectSessionSummary? {
        guard subjectFilter != allSubjectsToken else { return nil }
        let subject = subjectFilter
        let subjectSessions = modeSessions.filter {
            normalizeSubject($0.subject) == normalizeSubject(subject)
        }
        guard !subjectSessions.isEmpty else { return nil }

        let sessionNotes = subjectSessions
            .map { $0.notes.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let quickNotes = store.quickNotes
            .filter { normalizeSubject($0.subject) == normalizeSubject(subject) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let highlights = Array((sessionNotes + quickNotes).prefix(3))

        return SubjectSessionSummary(
            subject: subject,
            totalTime: subjectSessions.reduce(0) { $0 + $1.duration },
            filteredTime: filteredSessions.reduce(0) { $0 + $1.duration },
            sessionCount: subjectSessions.count,
            notesCount: sessionNotes.count + quickNotes.count,
            highlights: highlights
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("Overview", key: "overview", icon: "chart.bar.fill", color: .blue)
                if expandedSection.contains("overview") { overviewSection }

                sectionHeader("Smart Insights", key: "smart", icon: "sparkles", color: .purple)
                if expandedSection.contains("smart") { smartInsightsSection }

                sectionHeader("Sessions", key: "sessions", icon: "clock.fill", color: .green)
                if expandedSection.contains("sessions") { sessionsSection }

                sectionHeader("Insights", key: "insights", icon: "waveform.path.ecg", color: .orange)
                if expandedSection.contains("insights") { insightsSection }

                sectionHeader("XP & Achievements", key: "xp", icon: "bolt.fill", color: .yellow)
                if expandedSection.contains("xp") { GamificationView().padding(.horizontal, 20).padding(.bottom, 20) }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { animateIn = true }
            if subjectFilter != allSubjectsToken &&
                !availableSubjects.contains(where: { normalizeSubject($0) == normalizeSubject(subjectFilter) }) {
                subjectFilter = allSubjectsToken
            }
        }
        .onChange(of: modeStore.currentMode) { _ in
            resetSessionFilters()
            selectedDay = nil
        }
        .onChange(of: availableSubjects) { subjects in
            if subjectFilter != allSubjectsToken &&
                !subjects.contains(where: { normalizeSubject($0) == normalizeSubject(subjectFilter) }) {
                subjectFilter = allSubjectsToken
            }
        }
        .sheet(item: $editingSession) { s in SessionEditSheet(session: s) }
    }

    // ── Section header ────────────────────────────────────────────────────────

    func sectionHeader(_ title: String, key: String, icon: String, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if expandedSection.contains(key) { expandedSection.remove(key) }
                else { _ = expandedSection.insert(key) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: expandedSection.contains(key) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(color.opacity(0.04))
        }
        .buttonStyle(.plain)
    }

    // ── Overview ──────────────────────────────────────────────────────────────

    var overviewSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                let weekSecs = modeSessions
                    .filter { $0.startTime > Date().addingTimeInterval(-7*86400) }
                    .reduce(0.0) { $0 + $1.duration }
                let goal: Double = subStore.globalWeeklyGoalHours * 3600
                let pct = goal > 0 ? min(weekSecs / goal, 1.0) : 0
                let col: Color = pct >= 1 ? .green : pct >= 0.6 ? .blue : .orange

                // ── Weekly ring — tappable → week breakdown sheet ─────────────
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showWeeklyDetail.toggle()
                    }
                } label: {
                    ZStack {
                        Circle().stroke(col.opacity(0.12), lineWidth: 10).frame(width: 84, height: 84)
                        Circle()
                            .trim(from: 0, to: animateIn ? CGFloat(pct) : 0)
                            .stroke(col, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 84, height: 84).rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 1.0), value: animateIn)
                        VStack(spacing: 1) {
                            Text("\(Int(pct*100))%")
                                .font(.system(size: 17, weight: .bold)).foregroundColor(col)
                            Text("week").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    .shadow(color: col.opacity(showWeeklyDetail ? 0.4 : 0), radius: 10)
                }
                .buttonStyle(.plain)
                .help("Tap to see this week's breakdown")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    clickableMiniStat("Total", fmtDur(modeSessions.reduce(0){$0+$1.duration}),
                                      "clock", .blue) {
                        SubjectDashboardWindowController.show(subject:
                            modeSubjectTotals.first?.subject ?? "")
                    }
                    clickableMiniStat("Sessions", "\(modeSessions.count)",
                                      "checkmark.circle", .green) {
                        withAnimation { _ = expandedSection.insert("sessions") }
                    }
                    clickableMiniStat("Streak", "\(streak) days", "flame.fill", .red) {
                        withAnimation { showWeeklyDetail = true }
                    }
                    clickableMiniStat("Avg", avgSession, "timer", .orange) {
                        withAnimation { _ = expandedSection.insert("insights") }
                    }
                }
            }

            // Week breakdown — expands when ring is tapped
            if showWeeklyDetail {
                weekBreakdownCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Top subject — tappable → subject dashboard
            if let top = modeSubjectTotals.first {
                Button {
                    SubjectDashboardWindowController.show(subject: top.subject)
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(subStore.color(for: top.subject)).frame(width: 10, height: 10)
                            .shadow(color: subStore.color(for: top.subject).opacity(0.5), radius: 3)
                        (Text("Top: ").foregroundColor(.secondary) +
                         Text(top.subject).fontWeight(.semibold) +
                         Text(" · " + fmtDur(top.total)).foregroundColor(.secondary))
                            .font(.system(size: 12))
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11))
                            .foregroundColor(subStore.color(for: top.subject).opacity(0.7))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(subStore.color(for: top.subject).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(subStore.color(for: top.subject).opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Open \(top.subject) dashboard")
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .offset(y: animateIn ? 0 : 16).opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.05), value: animateIn)
    }

    // ── 7-day breakdown card ──────────────────────────────────────────────────

    var weekBreakdownCard: some View {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        let data: [(day: String, hours: Double)] = (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date())!
            let h = modeSessions.filter { cal.isDate($0.startTime, inSameDayAs: d) }
                        .reduce(0.0) { $0 + $1.duration } / 3600
            return (fmt.string(from: d), h)
        }
        let maxH = max(data.map(\.hours).max() ?? 1, 0.01)
        let goal = subStore.globalDailyGoalHours

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("This Week", systemImage: "calendar").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { withAnimation { showWeeklyDetail = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.system(size: 13))
                }.buttonStyle(.plain)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(data, id: \.day) { item in
                    VStack(spacing: 4) {
                        Text(item.hours > 0 ? String(format: "%.1f", item.hours) : "")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(item.hours >= goal ? .green : .secondary)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06)).frame(height: 50)
                            // Goal line indicator
                            if goal > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.15)).frame(height: 1)
                                    .offset(y: -(50 * CGFloat(min(goal/maxH, 1.0))))
                            }
                            if item.hours > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.hours >= goal
                                          ? Color.green.opacity(0.8)
                                          : Color.blue.opacity(0.7))
                                    .frame(height: 50 * CGFloat(item.hours / maxH))
                            }
                        }
                        Text(item.day).font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.15), lineWidth: 0.5))
    }

    // ── Clickable mini stat ───────────────────────────────────────────────────

    func clickableMiniStat(_ title: String, _ value: String, _ icon: String,
                           _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                    Text(title).font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundColor(color.opacity(0.4))
            }
            .padding(8).background(color.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // ── Legacy miniStat (kept for callers) ───────────────────────────────────

    func miniStat(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
                Text(title).font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(8).background(color.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // ── Sessions ──────────────────────────────────────────────────────────────

    // ── Smart Insights Section ───────────────────────────────────────────────

    var smartInsightsSection: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Focus Hour Insight
                if let hour = store.bestFocusHour() {
                    insightCard(
                        title: "Prime Time",
                        value: "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")",
                        subtitle: "Highest focus scores",
                        icon: "sun.max.fill",
                        color: .orange
                    )
                }

                // Productivity Day Insight
                if let day = store.mostProductiveDay() {
                    let dayName = Calendar.current.weekdaySymbols[day-1]
                    insightCard(
                        title: "Power Day",
                        value: dayName,
                        subtitle: "Most study time",
                        icon: "calendar",
                        color: .blue
                    )
                }
            }
            .padding(.horizontal, 20)

            // Attention Needed
            let needs = store.subjectsNeedingAttention()
            if !needs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Needs Attention")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(needs, id: \.self) { sub in
                                Text(sub)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(subStore.color(for: sub).opacity(0.15))
                                    .foregroundColor(subStore.color(for: sub))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            
            // AI Action
            Button { AIService.shared.detectStudyStyle() } label: {
                HStack {
                    Image(systemName: "ai.sparkles")
                    Text("Analyze Study Style with AI")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            if !AIService.shared.styleResult.isEmpty {
                Text(AIService.shared.styleResult)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
    }

    func insightCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 10, weight: .bold))
                Spacer()
            }
            .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
    }

    var sessionsSection: some View {
        let groupedFiltered = groupedByDay(filteredSessions)
        return VStack(spacing: 10) {
            if modeSessions.isEmpty {
                Text("No sessions in \(modeStore.currentMode.rawValue) mode yet — start the timer to record your first.")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .padding(.vertical, 30).frame(maxWidth: .infinity)
            } else {
                sessionFiltersCard
                    .padding(.horizontal, 20)

                if let summary = selectedSubjectSummary {
                    subjectSummaryCard(summary)
                        .padding(.horizontal, 20)
                }

                if filteredSessions.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("No sessions match these filters.")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Try a different subject or duration range.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(groupedFiltered.prefix(10), id: \.day) { group in
                        // Day header
                        HStack {
                            Text(group.day).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                            Spacer()
                            Text(fmtDur(group.sessions.reduce(0){$0+$1.duration}))
                                .font(.system(size: 11, design: .monospaced)).foregroundColor(.accentColor)
                        }
                        .padding(.horizontal, 24).padding(.vertical, 6)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))

                        ForEach(group.sessions) { s in
                            sessionRow(s)
                            Divider().padding(.leading, 56)
                        }
                    }
                    if groupedFiltered.count > 10 {
                        Text("Showing most recent 10 days — open full History in Analytics")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }

            // Clear all
            if !modeSessions.isEmpty {
                Button { confirmClearAll() } label: {
                    Label("Clear All Sessions", systemImage: "trash")
                        .font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain).padding(.vertical, 10)
            }
        }
    }

    var sessionFiltersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Session Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if hasActiveSessionFilters {
                    Button("Reset") { resetSessionFilters() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subject").font(.system(size: 10)).foregroundColor(.secondary)
                    Picker("Subject", selection: $subjectFilter) {
                        Text("All Subjects").tag(allSubjectsToken)
                        ForEach(availableSubjects, id: \.self) { sub in
                            Text(sub).tag(sub)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Time").font(.system(size: 10)).foregroundColor(.secondary)
                    Picker("Time", selection: $timeFilter) {
                        ForEach(SessionTimeFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration").font(.system(size: 10)).foregroundColor(.secondary)
                    Picker("Duration", selection: $durationFilter) {
                        ForEach(SessionDurationFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.14), lineWidth: 0.5))
    }

    func subjectSummaryCard(_ summary: SubjectSessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(subStore.color(for: summary.subject)).frame(width: 9, height: 9)
                Text(summary.subject).font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(summary.sessionCount) sessions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                summaryChip("Total Time", fmtDur(summary.totalTime), .blue)
                summaryChip("Shown Time", fmtDur(summary.filteredTime), .green)
                summaryChip("Notes", "\(summary.notesCount)", .purple)
            }

            if summary.highlights.isEmpty {
                Text("No notes saved for this subject yet.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Latest notes summary")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(Array(summary.highlights.enumerated()), id: \.offset) { _, note in
                        Text("• \(note)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.14), lineWidth: 0.5))
    }

    func summaryChip(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    func sessionRow(_ s: StudySession) -> some View {
        let tf = DateFormatter(); tf.timeStyle = .short
        let sc = subStore.color(for: s.subject)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(sc.opacity(0.12)).overlay(Circle().stroke(sc.opacity(0.3), lineWidth: 1))
                Text(String(s.subject.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold)).foregroundColor(sc)
            }
            .frame(width: 36, height: 36)
            .onTapGesture { SubjectDashboardWindowController.show(subject: s.subject) }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(s.subject).font(.system(size: 13, weight: .semibold))
                    if s.difficulty > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...s.difficulty, id: \.self) { i in
                                Image(systemName: "star.fill").font(.system(size: 7))
                                    .foregroundColor(diffColor(s.difficulty))
                            }
                        }
                    }
                }
                Text("\(tf.string(from: s.startTime)) · \(fmtDur(s.duration))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if !s.notes.isEmpty {
                    Text(s.notes).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { SessionReplayWindowController.present(s) } label: {
                    Image(systemName: "play.circle.fill").font(.system(size: 18)).foregroundColor(sc.opacity(0.7))
                }.buttonStyle(.plain)
                Button { editingSession = s } label: {
                    Image(systemName: "pencil.circle.fill").font(.system(size: 18)).foregroundColor(.orange.opacity(0.75))
                }.buttonStyle(.plain)
                Button { SessionStore.shared.delete(s) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundColor(.red.opacity(0.4))
                        .frame(width: 24, height: 24).background(Color.red.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    // ── Insights ──────────────────────────────────────────────────────────────

    var insightsSection: some View {
        VStack(spacing: 14) {
            if modeSessions.isEmpty {
                Text("No session data for insights yet.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                // ── 7-day bar chart — tappable ────────────────────────────────
                barChartCard

                // ── Distraction card — tappable ───────────────────────────────
                let analysis = DistractionAnalysis.analyse(sessions: modeSessions)
                if analysis.totalDistractions > 0 {
                    distractionCard(analysis)
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.6)) { animateChart = true }
            }
        }
    }

    // ── Animated bar chart ────────────────────────────────────────────────────

    var barChartCard: some View {
        let data = last7DaysData()
        let maxH = max(data.map(\.hours).max() ?? 1, 0.01)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Last 7 Days", systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if selectedDay != nil {
                    Button { withAnimation { selectedDay = nil } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }

            // Custom animated bars (avoid Chart overlay complexity)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(data, id: \.day) { item in
                    let isSelected = selectedDay == item.day
                    VStack(spacing: 4) {
                        // Value label above bar
                        Text(item.hours > 0 ? String(format: "%.1f", item.hours) : "")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(isSelected ? .blue : .secondary)
                            .fontWeight(isSelected ? .bold : .regular)

                        // Bar
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
                                .frame(height: 80)
                            if item.hours > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isSelected
                                          ? LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top)
                                          : LinearGradient(colors: [.blue.opacity(0.5), .blue.opacity(0.8)],
                                                           startPoint: .bottom, endPoint: .top))
                                    .frame(height: animateChart
                                           ? 80 * CGFloat(item.hours / maxH)
                                           : 0)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.7)
                                                .delay(Double(data.firstIndex(where: { $0.day == item.day }) ?? 0) * 0.05),
                                               value: animateChart)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDay = isSelected ? nil : item.day
                            }
                        }

                        Text(item.day).font(.system(size: 9))
                            .foregroundColor(isSelected ? .blue : .secondary)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 106)

            // Drill-down: sessions for selected day
            if let day = selectedDay {
                let daySessions = sessionsForDay(day)
                if !daySessions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sessions on \(day)")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.blue)
                        ForEach(daySessions.prefix(5)) { s in
                            HStack(spacing: 8) {
                                Circle().fill(subStore.color(for: s.subject)).frame(width: 6, height: 6)
                                Text(s.subject).font(.system(size: 11)).lineLimit(1)
                                Spacer()
                                Text(fmtDur(s.duration))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.blue.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.1), lineWidth: 0.5))
    }

    // ── Distraction card — tappable ───────────────────────────────────────────

    func distractionCard(_ analysis: DistractionAnalysis) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedHour = selectedHour == nil ? -1 : nil  // toggle detail
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Distraction Pattern", systemImage: "bolt.slash.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        Text(analysis.insightText)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(analysis.totalDistractions)")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(.orange)
                        Text("total").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    Image(systemName: selectedHour == nil ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }

                // Expanded: top distraction subjects
                if selectedHour != nil {
                    Divider().overlay(Color.orange.opacity(0.2))
                    let bySubject = Dictionary(
                        grouping: modeSessions.filter { !$0.distractions.isEmpty },
                        by: { $0.subject }
                    )
                    .mapValues { sessions in sessions.reduce(0) { $0 + $1.distractions.count } }
                    .sorted { $0.value > $1.value }
                    .prefix(4)
                    ForEach(Array(bySubject), id: \.key) { pair in
                        HStack(spacing: 8) {
                            Circle().fill(subStore.color(for: pair.key)).frame(width: 6, height: 6)
                            Text(pair.key.isEmpty ? "Untagged" : pair.key)
                                .font(.system(size: 11)).lineLimit(1)
                            Spacer()
                            Text("\(pair.value) distr.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(selectedHour != nil ? 0.3 : 0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selectedHour)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func sessionsForDay(_ dayLabel: String) -> [StudySession] {
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        let cal = Calendar.current
        return modeSessions.filter {
            fmt.string(from: $0.startTime) == dayLabel &&
            cal.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    struct DayData { var day: String; var hours: Double }

    func last7DaysData() -> [DayData] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        return (0..<7).reversed().map { offset -> DayData in
            let day = cal.date(byAdding: .day, value: -offset, to: Date())!
            let h   = modeSessions
                .filter { cal.isDate($0.startTime, inSameDayAs: day) }
                .reduce(0.0) { $0 + $1.duration } / 3600
            return DayData(day: fmt.string(from: day), hours: h)
        }
    }

    var streak: Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while modeSessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var avgSession: String {
        guard !modeSessions.isEmpty else { return "—" }
        return fmtDur(modeSessions.reduce(0){$0+$1.duration} / Double(modeSessions.count))
    }

    func groupedByDay(_ sessions: [StudySession]) -> [(day: String, sessions: [StudySession])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { date in
            let daySessions = sortSessions(grouped[date] ?? [])
            return (fmt.string(from: date), daySessions)
        }
    }

    func sortSessions(_ sessions: [StudySession]) -> [StudySession] {
        sessions.sorted { a, b in
            if a.startTime != b.startTime { return a.startTime > b.startTime }
            if a.endTime != b.endTime { return a.endTime > b.endTime }
            return a.id.uuidString > b.id.uuidString
        }
    }

    func normalizeSubject(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func resetSessionFilters() {
        subjectFilter = allSubjectsToken
        timeFilter = .allTime
        durationFilter = .all
    }

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func diffColor(_ d: Int) -> Color {
        [.red, .orange, .yellow, Color(red:0.6,green:0.9,blue:0.2), .green][max(0, d-1)]
    }

    func confirmClearAll() {
        let a = NSAlert()
        a.messageText = "Delete All Sessions?"
        a.informativeText = "This deletes sessions from all modes and cannot be undone."
        a.addButton(withTitle: "Delete All"); a.addButton(withTitle: "Cancel")
        a.alertStyle = .critical
        if a.runModal() == .alertFirstButtonReturn { store.deleteAll() }
    }
}
