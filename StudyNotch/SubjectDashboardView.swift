import SwiftUI
import AppKit
import Charts

// ── Subject Dashboard Window ──────────────────────────────────────────────────

class SubjectDashboardWindowController: NSWindowController {
    static var windows: [String: SubjectDashboardWindowController] = [:]

    static func show(subject: String) {
        if let existing = windows[subject] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title              = subject
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.minSize            = NSSize(width: 480, height: 520)
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: SubjectDashboardView(subject: subject))
        let c = SubjectDashboardWindowController(window: win)
        windows[subject] = c
        c.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in SubjectDashboardWindowController.windows.removeValue(forKey: subject) }
    }
}

// ── Subject Dashboard View ────────────────────────────────────────────────────

struct SubjectDashboardView: View {
    let subject: String

    var sessions   = SessionStore.shared
    var subStore   = SubjectStore.shared
    var taskStore  = TaskStore.shared
    var modeStore  = ModeStore.shared

    @State private var animateIn = false
    @State private var selectedTab = 0   // 0=Overview 1=Sessions 2=Tasks

    private let accent: Color
    init(subject: String) {
        self.subject = subject
        self.accent = SubjectStore.shared.color(for: subject)
    }

    // ── Computed stats ────────────────────────────────────────────────────────

    var subjectSessions: [StudySession] {
        sessions.sessions.filter { $0.subject == subject }
    }
    var totalTime    : TimeInterval { subjectSessions.reduce(0) { $0 + $1.duration } }
    var thisWeek     : TimeInterval {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return subjectSessions.filter { $0.startTime > cutoff }.reduce(0) { $0 + $1.duration }
    }
    var sessionCount : Int { subjectSessions.count }
    var avgDuration  : TimeInterval {
        guard sessionCount > 0 else { return 0 }
        return totalTime / Double(sessionCount)
    }
    var avgDifficulty: Double {
        let rated = subjectSessions.filter { $0.difficulty > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.map(\.difficulty).reduce(0,+)) / Double(rated.count)
    }
    var streak: Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while subjectSessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }
    var pendingTasks : [StudyTask] {
        taskStore.tasks.filter { !$0.isCompleted && $0.subject == subject }
    }
    var completedTasks: [StudyTask] {
        taskStore.tasks.filter { $0.isCompleted && $0.subject == subject }
    }
    var exam: ExamEntry? {
        subStore.exams.filter { $0.subject == subject }
            .sorted { $0.daysUntil < $1.daysUntil }.first
    }
    var weeklyGoal: Double {
        subStore.weeklyGoals.first { $0.subject == subject }?.weeklyHours ?? 0
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
            tabBar
            Divider().overlay(accent.opacity(0.15))
            Group {
                switch selectedTab {
                case 1: sessionsTab
                case 2: tasksTab
                case 3: reviewTab
                case 4: distractionsTab
                default: overviewTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                animateIn = true
            }
        }
    }

    // ── Hero header ───────────────────────────────────────────────────────────

    var heroHeader: some View {
        ZStack(alignment: .bottom) {
            // Gradient background with subject colour
            LinearGradient(
                colors: [accent.opacity(0.35), accent.opacity(0.05), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 130)

            // Glow blob
            Circle()
                .fill(accent.opacity(0.25))
                .blur(radius: 40)
                .frame(width: 220, height: 80)
                .offset(y: -10)

            HStack(alignment: .bottom, spacing: 16) {
                // Subject colour orb
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 54, height: 54)
                    Circle()
                        .fill(accent)
                        .frame(width: 36, height: 36)
                        .shadow(color: accent, radius: 10)
                }
                .scaleEffect(animateIn ? 1.0 : 0.4)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: animateIn)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subject)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        Text(fmtDur(totalTime) + " total")
                            .font(.system(size: 12)).foregroundColor(accent)
                        Text("·").foregroundColor(.white.opacity(0.3))
                        Text("\(sessionCount) sessions")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        if let e = exam, e.daysUntil > 0 {
                            Text("·").foregroundColor(.white.opacity(0.3))
                            Text("Exam in \(Int(e.daysUntil))d")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(e.daysUntil <= 3 ? .red : .orange)
                        }
                    }
                }
                Spacer()

                // Quick-start button
                Button {
                    StudyTimer.shared.currentSubject = subject
                    subStore.ensureMeta(for: subject)
                    StudyTimer.shared.start()
                    NSApp.windows.forEach { if $0.title == subject { $0.close() } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Start Session").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(accent)
                    .clipShape(Capsule())
                    .shadow(color: accent.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    // ── Tab bar ───────────────────────────────────────────────────────────────

    var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tabBtn("Overview",      icon: "square.grid.2x2",    idx: 0)
                tabBtn("Sessions",      icon: "clock",               idx: 1)
                tabBtn("Tasks (\(pendingTasks.count))", icon: "checklist", idx: 2)
                tabBtn("Review",        icon: "arrow.clockwise",     idx: 3)
                tabBtn("Distractions",  icon: "bolt.slash",          idx: 4)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    func tabBtn(_ label: String, icon: String, idx: Int) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { selectedTab = idx } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: selectedTab == idx ? .semibold : .regular))
            }
            .foregroundColor(selectedTab == idx ? accent : .white.opacity(0.4))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                if selectedTab == idx {
                    Capsule().fill(accent).frame(height: 2)
                        .padding(.horizontal, 10)
                        .transition(.scale)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ── Overview tab ──────────────────────────────────────────────────────────

    var overviewTab: some View {
        ScrollView {
            VStack(spacing: 18) {

                // ── Stat grid ─────────────────────────────────────────────────
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 10) {
                    miniStat("Total",    fmtDur(totalTime),    "clock.fill",         .blue,   delay: 0.05)
                    miniStat("This Week",fmtDur(thisWeek),     "calendar",           accent,  delay: 0.10)
                    miniStat("Sessions", "\(sessionCount)",    "checkmark.circle",   .green,  delay: 0.15)
                    miniStat("Streak",   "\(streak)d",         "flame.fill",         .red,    delay: 0.20)
                    miniStat("Avg",      fmtDur(avgDuration),  "timer",              .orange, delay: 0.25)
                    miniStat("Difficulty",avgDifficulty > 0 ? String(format:"%.1f★",avgDifficulty) : "—",
                             "star.fill", .yellow, delay: 0.30)
                    miniStat("Tasks done","\(completedTasks.count)","checkmark.seal.fill",.teal, delay: 0.35)
                    miniStat("Pending",  "\(pendingTasks.count)","list.bullet",       pendingTasks.isEmpty ? .secondary : .orange, delay: 0.40)
                }

                // ── Exam card ─────────────────────────────────────────────────
                if let e = exam { examCard(e) }

                // ── Weekly goal ring ──────────────────────────────────────────
                if weeklyGoal > 0 { weeklyGoalCard }

                // ── Focus Score Card ──────────────────────────────────────────
                if sessionCount > 0 { focusScoreCard }

                // ── 7-day heatmap ─────────────────────────────────────────────
                heatmapCard

                // ── Top tasks preview ─────────────────────────────────────────
                if !pendingTasks.isEmpty { topTasksCard }
            }
            .padding(16)
        }
    }

    // ── Mini stat card ────────────────────────────────────────────────────────

    func miniStat(_ title: String, _ value: String, _ icon: String,
                  _ color: Color, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.12), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 16).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(delay), value: animateIn)
    }

    // ── Exam card ─────────────────────────────────────────────────────────────

    func examCard(_ e: ExamEntry) -> some View {
        let days = Int(e.daysUntil)
        let urgent = days <= 3
        let c: Color = urgent ? .red : days <= 7 ? .orange : .blue
        let pct = min(1.0, Double(7 - days) / 7.0)

        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(c.opacity(0.15), lineWidth: 5).frame(width: 52, height: 52)
                Circle().trim(from: 0, to: CGFloat(pct))
                    .stroke(c, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 52, height: 52).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(size: 14, weight: .bold)).foregroundColor(c)
                    Text("days").font(.system(size: 7)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Exam" + (urgent ? " 🚨" : " 📅"))
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Text(e.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if !e.location.isEmpty {
                    Label(e.location, systemImage: "mappin.circle")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(c.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(c.opacity(0.25), lineWidth: 1))
    }

    // ── Weekly goal ring card ─────────────────────────────────────────────────

    var weeklyGoalCard: some View {
        let actual = subStore.actualHoursThisWeek(subject: subject, sessions: sessions.sessions)
        let pct    = weeklyGoal > 0 ? min(1.0, actual / weeklyGoal) : 0
        return HStack(spacing: 16) {
            GoalRing(progress: pct, color: accent, size: 56, lineWidth: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Goal").font(.system(size: 13, weight: .semibold))
                Text(String(format: "%.1fh / %.0fh", actual, weeklyGoal))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(pct >= 1 ? .green : accent)
                Text(pct >= 1 ? "Goal reached! 🎉" : String(format: "%.1fh remaining", weeklyGoal - actual))
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.15), lineWidth: 0.5))
    }
    
    // ── Focus Score Card ──────────────────────────────────────────────────────

    var focusScoreCard: some View {
        let history = sessions.focusScoreHistory(for: subject, limit: 10)
        let avgScore = sessions.averageFocusScore(for: subject)
        let trend = sessions.focusTrend(for: subject)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile").foregroundColor(accent)
                Text("Focus Score (Last \(history.count))")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("\(avgScore)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(), value: avgScore)
                    
                    if abs(trend) > 0.5 {
                        Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(trend > 0 ? .green : .red)
                    }
                }
            }
            
            if history.count > 1 {
                Chart {
                    ForEach(Array(history.enumerated()), id: \.offset) { idx, session in
                        LineMark(
                            x: .value("Session", idx),
                            y: .value("Score", session.focusScore)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        AreaMark(
                            x: .value("Session", idx),
                            yStart: .value("Min", 0),
                            yEnd: .value("Score", session.focusScore)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(
                            colors: [accent.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        
                        PointMark(
                            x: .value("Session", idx),
                            y: .value("Score", session.focusScore)
                        )
                        .foregroundStyle(accent)
                    }
                }
                .chartYScale(domain: .automatic)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2]))
                            .foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel() {
                            if let intVal = value.as(Int.self) {
                                Text("\(intVal)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .frame(height: 80)
            } else {
                Text("More sessions needed for trend chart.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                    .frame(height: 40)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    // ── 7-day heatmap ─────────────────────────────────────────────────────────

    var heatmapCard: some View {
        let data = subStore.heatmapData(subject: subject, sessions: sessions.sessions, days: 7)
        let maxH = (data.map(\.hours).max() ?? 1)
        let fmt  = DateFormatter(); fmt.dateFormat = "EEE"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock").foregroundColor(accent)
                Text("Last 7 Days").font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 4) {
                ForEach(data) { day in
                    VStack(spacing: 4) {
                        Text(fmt.string(from: day.date))
                            .font(.system(size: 8)).foregroundColor(.secondary)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.06)).frame(height: 44)
                            if day.hours > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(
                                        colors: [accent.opacity(0.5), accent],
                                        startPoint: .bottom, endPoint: .top))
                                    .frame(height: max(4, 44 * CGFloat(day.hours / maxH)))
                            }
                        }
                        Text(day.hours < 0.1 ? "–"
                             : day.hours < 1 ? String(format:"%.0fm", day.hours*60)
                             : String(format:"%.1fh", day.hours))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    // ── Top tasks preview ─────────────────────────────────────────────────────

    var topTasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist").foregroundColor(accent)
                Text("Pending Tasks (\(pendingTasks.count))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("View All") { withAnimation { selectedTab = 2 } }
                    .font(.system(size: 11)).foregroundColor(accent).buttonStyle(.plain)
            }
            ForEach(pendingTasks.prefix(4)) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.isOverdue ? "exclamationmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(task.isOverdue ? .red : .white.opacity(0.3))
                    Text(task.title).font(.system(size: 12)).lineLimit(1).foregroundColor(.white.opacity(0.8))
                    Spacer()
                    if let d = task.dueDate {
                        Text(d.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.12), lineWidth: 0.5))
    }

    // ── Sessions tab ──────────────────────────────────────────────────────────

    var sessionsTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                if subjectSessions.isEmpty {
                    emptyState("No sessions yet", "calendar.badge.exclamationmark")
                } else {
                    ForEach(subjectSessions.prefix(50)) { s in
                        sessionRow(s)
                        Divider().overlay(Color.white.opacity(0.05))
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    func sessionRow(_ s: StudySession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.8))
                HStack(spacing: 6) {
                    Text(s.startTime.formatted(.dateTime.hour().minute()))
                    Text("–")
                    Text(s.endTime.formatted(.dateTime.hour().minute()))
                }
                .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(fmtDur(s.duration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                if s.difficulty > 0 {
                    HStack(spacing: 1) {
                        ForEach(1...s.difficulty, id: \.self) { _ in
                            Image(systemName: "star.fill").font(.system(size: 7)).foregroundColor(.yellow)
                        }
                    }
                }
            }
            if s.distractions.count > 0 {
                Label("\(s.distractions.count)", systemImage: "bolt.slash")
                    .font(.system(size: 9)).foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // ── Tasks tab ─────────────────────────────────────────────────────────────

    var tasksTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                if pendingTasks.isEmpty && completedTasks.isEmpty {
                    emptyState("No tasks for this subject", "checklist")
                } else {
                    if !pendingTasks.isEmpty {
                        sectionHeader("Pending (\(pendingTasks.count))")
                        ForEach(pendingTasks) { t in
                            compactTaskRow(t)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                    if !completedTasks.isEmpty {
                        sectionHeader("Completed (\(completedTasks.count))")
                        ForEach(completedTasks.prefix(20)) { t in
                            compactTaskRow(t).opacity(0.5)
                            Divider().overlay(Color.white.opacity(0.04))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func compactTaskRow(_ t: StudyTask) -> some View {
        HStack(spacing: 10) {
            Button {
                if t.isCompleted { taskStore.uncomplete(t) } else { taskStore.complete(t) }
            } label: {
                Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(t.isCompleted ? .green : t.isOverdue ? .red : .white.opacity(0.35))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 12)).strikethrough(t.isCompleted)
                    .foregroundColor(t.isCompleted ? .secondary : .white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 5) {
                    if t.taskType != .general {
                        Label(t.taskType.rawValue, systemImage: t.taskType.icon)
                            .font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    if t.taskTotal > 0 {
                        Text("\(t.taskDone)/\(t.taskTotal) \(t.taskType.unit)")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(accent.opacity(0.8))
                    }
                }
            }
            Spacer()
            if let d = t.dueDate {
                Text(d.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10))
                    .foregroundColor(t.isOverdue ? .red : t.dueSoon ? .orange : .secondary)
            }
            Button { taskStore.duplicate(t) } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Duplicate task")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // ── Review tab (Spaced Repetition) ──────────────────────────────────────

    var reviewTab: some View {
        let srStatus = SpacedRepetitionService.shared
            .statusForAllSubjects()
            .filter { $0.subject == subject }
            .first

        return ScrollView {
            VStack(spacing: 16) {
                if let sr = srStatus {
                    // Status card
                    let urgencyColor: Color = {
                        switch sr.urgency {
                        case .critical: return .red
                        case .overdue:  return .orange
                        case .soon:     return .yellow
                        case .ok:       return .green
                        }
                    }()

                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(urgencyColor.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                Image(systemName: sr.isOverdue ? "exclamationmark.arrow.circlepath" : "checkmark.arrow.trianglehead.counterclockwise")
                                    .font(.system(size: 22)).foregroundColor(urgencyColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sr.isOverdue ? "Review Overdue" : sr.urgency == .soon ? "Review Soon" : "On Track")
                                    .font(.system(size: 16, weight: .bold)).foregroundColor(urgencyColor)
                                Text("Last studied: \(sr.daysSince) day\(sr.daysSince == 1 ? "" : "s") ago")
                                    .font(.system(size: 12)).foregroundColor(.secondary)
                                Text("Recommended every: \(sr.interval) days")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        // Progress bar
                        let pct = min(1.0, Double(sr.daysSince) / Double(sr.interval))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.08)).frame(height: 10)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(colors: [urgencyColor.opacity(0.7), urgencyColor],
                                                         startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * CGFloat(pct), height: 10)
                            }
                        }.frame(height: 10)

                        HStack {
                            Text("Last reviewed").font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text("Due now").font(.system(size: 10)).foregroundColor(urgencyColor)
                        }

                        // Difficulty info
                        let diffLabel = sr.avgDiff <= 2 ? "Hard ⭐" : sr.avgDiff <= 3.5 ? "Medium ⭐⭐⭐" : "Easy ⭐⭐⭐⭐⭐"
                        Text("Avg difficulty: \(diffLabel) — interval adjusted accordingly")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Quick start button
                        Button {
                            StudyTimer.shared.currentSubject = subject
                            subStore.ensureMeta(for: subject)
                            StudyTimer.shared.start()
                        } label: {
                            Label("Start Review Session Now", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(urgencyColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(urgencyColor.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(urgencyColor.opacity(0.2), lineWidth: 0.5))

                    // SM-2 explanation
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle").font(.system(size: 12, weight: .semibold))
                        Text("StudyNotch uses spaced repetition (SM-2 algorithm) to calculate the optimal review interval for each subject based on how often you study it and how hard you find it. Hard subjects get shorter intervals; easy subjects get longer ones.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                } else {
                    emptyState("No sessions yet for spaced repetition", "arrow.clockwise")
                }
            }
            .padding(16)
        }
    }

    // ── Distractions tab ──────────────────────────────────────────────────────

    var distractionsTab: some View {
        let subjectSessions = sessions.sessions.filter { $0.subject == subject }
        let analysis = DistractionAnalysis.analyse(sessions: subjectSessions)

        return ScrollView {
            VStack(spacing: 14) {
                if analysis.totalDistractions == 0 {
                    emptyState("No distractions logged for this subject", "bolt.slash")
                } else {
                    // Stats row
                    HStack(spacing: 10) {
                        distrMini("Total", "\(analysis.totalDistractions)", "bolt.slash.fill", .red)
                        distrMini("Per Session", String(format: "%.1f", analysis.avgPerSession), "chart.bar", .orange)
                        distrMini("Trend", analysis.trend > 0 ? "↑ Worse" : "↓ Better",
                                  analysis.trend > 0 ? "arrow.up.right" : "arrow.down.right",
                                  analysis.trend > 0 ? .red : .green)
                    }

                    // Insight
                    if !analysis.insightText.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 13)).foregroundColor(.purple)
                            Text(analysis.insightText)
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Label breakdown
                    if !analysis.byLabel.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Distraction Types", systemImage: "tag.fill")
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(analysis.byLabel.prefix(4)) { item in
                                HStack(spacing: 8) {
                                    Text(item.label).font(.system(size: 11))
                                        .frame(width: 70, alignment: .leading)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.white.opacity(0.06)).frame(height: 7)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(accent.opacity(0.7))
                                                .frame(width: geo.size.width * CGFloat(item.pct), height: 7)
                                        }
                                    }.frame(height: 7)
                                    Text("\(Int(item.pct * 100))%")
                                        .contentTransition(.numericText())
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: item.pct)
                                        .font(.system(size: 9)).foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .trailing)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
    }

    func distrMini(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ── Empty state ───────────────────────────────────────────────────────────────

    func emptyState(_ message: String, _ icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32)).foregroundColor(.white.opacity(0.15))
            Text(message).font(.system(size: 13)).foregroundColor(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
