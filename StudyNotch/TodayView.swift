import SwiftUI
import AppKit
import Charts

// ── Today Screen Window ───────────────────────────────────────────────────────

class TodayWindowController: NSWindowController {
    static var shared: TodayWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "Today"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.minSize = NSSize(width: 360, height: 500)
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: TodayView())
        let c = TodayWindowController(window: win)
        shared = c
        c.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in TodayWindowController.shared = nil }
    }
}

// ── Today View — Premium Redesign ─────────────────────────────────────────────

struct TodayView: View {
    var sessions   = SessionStore.shared
    var tasks      = TaskStore.shared
    var subStore   = SubjectStore.shared
    var timer      = StudyTimer.shared
    var gcal       = GoogleCalendarService.shared
    var streak     = StreakStore.shared

    @State private var animateIn     = false
    @State private var ringAnimate   = false
    @State private var aiSuggestion  = ""
    @State private var loadingAI     = false
    @State private var showShareCard = false
    @State private var showHeatmap   = false

    // ── Computed ──────────────────────────────────────────────────────────────

    var todaySessions: [StudySession] {
        sessions.sessions.filter { Calendar.current.isDateInToday($0.startTime) }
    }
    var todayHours  : Double { todaySessions.reduce(0) { $0 + $1.duration } / 3600 }
    var todayGoal   : Double { max(0.5, subStore.globalDailyGoalHours) }
    var progressPct : Double { min(1.0, todayHours / todayGoal) }

    var nextTask: StudyTask? {
        tasks.tasks.filter { !$0.isCompleted }
            .sorted { a, b in
                if a.isOverdue != b.isOverdue { return a.isOverdue }
                if a.priority  != b.priority  { return a.priority.rawValue > b.priority.rawValue }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }.first
    }
    var nextExam: ExamEntry? {
        subStore.exams.filter { $0.daysUntil > 0 }.sorted { $0.daysUntil < $1.daysUntil }.first
    }

    var ringColor: Color {
        progressPct >= 1 ? .green : progressPct >= 0.5 ? Color(red:0.2,green:0.7,blue:1) : Color(red:1.0,green:0.6,blue:0.2)
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            // Deep background
            LinearGradient(
                colors: [Color(red:0.05,green:0.05,blue:0.10),
                         Color(red:0.03,green:0.03,blue:0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            // Ambient glow from ring colour
            Circle()
                .fill(ringColor.opacity(0.07))
                .blur(radius: 60)
                .frame(width: 300, height: 300)
                .offset(x: -60, y: -120)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    headerRow
                    heroProgressCard
                    streakCard
                    quickActionsRow
                    if let t = nextTask  { nextTaskCard(t)  }
                    if let e = nextExam  { nextExamCard(e)  }
                    if !aiSuggestion.isEmpty { aiCard }
                    if !todaySessions.isEmpty { sessionsCard }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { animateIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 1.1)) { ringAnimate = true }
            }
            streak.rebuild()
            if gcal.isConnected { gcal.fetchTodayEvents() }
            generateAISuggestion()
        }
        .sheet(isPresented: $showShareCard) { ShareCardView() }
    }

    // ── Header row ────────────────────────────────────────────────────────────

    var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            // Streak flame badge
            if streak.currentStreak > 0 {
                VStack(spacing: 1) {
                    Text("🔥")
                        .font(.system(size: 18))
                        .scaleEffect(animateIn ? 1.0 : 0.5)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.3), value: animateIn)
                    Text("\(streak.currentStreak)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 0.5))
            }
            Button { showShareCard = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .offset(y: animateIn ? 0 : -14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.03), value: animateIn)
    }

    // ── Hero progress card ────────────────────────────────────────────────────

    var heroProgressCard: some View {
        HStack(spacing: 20) {
            // Arc ring
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.12), lineWidth: 9)
                    .frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: ringAnimate ? CGFloat(progressPct) : 0)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor.opacity(0.6), ringColor],
                            center: .center, startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * progressPct)
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.5), radius: 6)
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", todayHours))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(ringColor)
                    Text("h").font(.system(size: 10)).foregroundColor(ringColor.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // Big time label
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f%%", progressPct * 100))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(ringColor)
                    Text("of daily goal")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                // Sessions & goal
                HStack(spacing: 10) {
                    Label("\(todaySessions.count) sessions", systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Label("Goal \(String(format:"%.0f",todayGoal))h", systemImage: "target")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [ringColor.opacity(0.7), ringColor],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: ringAnimate
                                   ? geo.size.width * CGFloat(progressPct) : 0,
                                   height: 5)
                            .animation(.easeOut(duration: 1.0).delay(0.25), value: ringAnimate)
                    }
                }.frame(height: 5)

                if progressPct >= 1 {
                    Label("Goal reached! 🎉", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(ringColor.opacity(0.06))
                RoundedRectangle(cornerRadius: 18)
                    .stroke(LinearGradient(
                        colors: [ringColor.opacity(0.3), ringColor.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8)
            }
        )
        .offset(y: animateIn ? 0 : 18).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08), value: animateIn)
    }

    // ── Streak card ───────────────────────────────────────────────────────────

    var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Stats row
                HStack(spacing: 16) {
                    streakStat("🔥", "\(streak.currentStreak)", "Current")
                    Divider().frame(height: 28).overlay(Color.white.opacity(0.08))
                    streakStat("🏆", "\(streak.longestStreak)", "Longest")
                    Divider().frame(height: 28).overlay(Color.white.opacity(0.08))
                    streakStat("📅", "\(streak.totalStudyDays)", "Days studied")
                }
                Spacer()
                // Freeze button
                Button {
                    streak.freezeToday()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "snowflake").font(.system(size: 10))
                        Text(streak.canFreeze ? "Freeze" : "Used")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(streak.canFreeze ? Color(red:0.4,green:0.8,blue:1) : .secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(streak.canFreeze
                                ? Color(red:0.4,green:0.8,blue:1).opacity(0.1)
                                : Color.white.opacity(0.04))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!streak.canFreeze)
                .help("Protect today's streak even if you don't study")

                // Expand heatmap
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showHeatmap.toggle()
                    }
                } label: {
                    Image(systemName: showHeatmap ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Last 7 days quick view
            last7DaysRow

            // Full heatmap (expandable)
            if showHeatmap {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 12 Weeks")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    StreakHeatmapView()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.orange.opacity(0.12), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 16).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: animateIn)
    }

    func streakStat(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(emoji).font(.system(size: 13))
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    var last7DaysRow: some View {
        let cal = Calendar.current
        let fmt = StreakStore.keyFormatter
        let days: [(label: String, key: String, studied: Bool)] = (0..<7).reversed().map { offset in
            let d   = cal.date(byAdding: .day, value: -offset, to: Date())!
            let key = fmt.string(from: d)
            let lbl = offset == 0 ? "T" : String(cal.shortWeekdaySymbols[cal.component(.weekday,from:d)-1].prefix(1))
            return (lbl, key, streak.studiedDates.contains(key) || streak.frozenDates.contains(key))
        }
        return HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(day.studied
                                  ? Color.orange.opacity(0.8)
                                  : Color.white.opacity(0.07))
                            .frame(width: 26, height: 26)
                        if day.studied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    Text(day.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(day.studied ? .orange : .secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // ── Quick actions ─────────────────────────────────────────────────────────

    var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickAction("Start", "play.fill",        Color(red:0.2,green:1.0,blue:0.55)) { StudyTimer.shared.start() }
            quickAction("Log",   "square.and.pencil", Color(red:0.4,green:0.7,blue:1.0)) { SessionEndWindowController.presentManual() }
            quickAction("Plan",  "calendar",          Color(red:0.7,green:0.4,blue:1.0)) { StudyPlanWindowController.show() }
            quickAction("AI",    "brain.head.profile", Color(red:0.8,green:0.4,blue:1.0)) { AIChatWindowController.show() }
        }
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.16), value: animateIn)
    }

    func quickAction(_ label: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(color.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // ── Next task card ────────────────────────────────────────────────────────

    func nextTaskCard(_ t: StudyTask) -> some View {
        let color: Color = t.isOverdue ? .red : t.priority == .high ? .orange : Color(red:0.4,green:0.7,blue:1)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15)).frame(width: 42, height: 42)
                Image(systemName: t.isOverdue ? "exclamationmark.circle.fill" : t.taskType.icon)
                    .font(.system(size: 18)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("NEXT TASK")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(color.opacity(0.6))
                        .tracking(0.8)
                    if t.isOverdue {
                        Text("OVERDUE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red).clipShape(Capsule())
                    }
                }
                Text(t.title)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !t.subject.isEmpty {
                        Circle().fill(subStore.color(for: t.subject)).frame(width: 5, height: 5)
                        Text(t.subject).font(.system(size: 10)).foregroundColor(subStore.color(for: t.subject))
                    }
                    if let d = t.dueDate {
                        Text(d.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button { tasks.complete(t) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24)).foregroundColor(.green.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.20), value: animateIn)
    }

    // ── Next exam card ────────────────────────────────────────────────────────

    func nextExamCard(_ e: ExamEntry) -> some View {
        let days = Int(e.daysUntil)
        let color: Color = days <= 1 ? .red : days <= 3 ? .orange : Color(red:0.4,green:0.7,blue:1)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15)).frame(width: 42, height: 42)
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(size: 16, weight: .black)).foregroundColor(color)
                    Text(days == 1 ? "day" : "days").font(.system(size: 7)).foregroundColor(color.opacity(0.7))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT EXAM").font(.system(size: 8, weight: .bold))
                    .foregroundColor(color.opacity(0.6)).tracking(0.8)
                Text(e.subject).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(e.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            if days <= 3 {
                Text("Soon!")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.15)).clipShape(Capsule())
            }
        }
        .padding(14)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.24), value: animateIn)
    }

    // ── AI suggestion card ────────────────────────────────────────────────────

    var aiCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 15)).foregroundColor(.purple)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("AI COACH").font(.system(size: 8, weight: .bold))
                    .foregroundColor(.purple.opacity(0.6)).tracking(0.8)
                if loadingAI {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Thinking…").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                } else {
                    Text(aiSuggestion)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { generateAISuggestion() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.purple.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.15), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.28), value: animateIn)
    }

    // ── Today sessions card ───────────────────────────────────────────────────

    var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S SESSIONS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary).tracking(0.8)
                Spacer()
                Text(fmtDur(todaySessions.reduce(0){$0+$1.duration}))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            ForEach(todaySessions.prefix(5).reversed()) { s in
                HStack(spacing: 10) {
                    Circle()
                        .fill(subStore.color(for: s.subject))
                        .frame(width: 7, height: 7)
                        .shadow(color: subStore.color(for: s.subject).opacity(0.6), radius: 2)
                    Text(s.subject)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8)).lineLimit(1)
                    Spacer()
                    Text(fmtDur(s.duration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(subStore.color(for: s.subject))
                    if s.difficulty > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...s.difficulty, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7)).foregroundColor(.yellow.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(subStore.color(for: s.subject).opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { SubjectDashboardWindowController.show(subject: s.subject) }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32), value: animateIn)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h <  6 { return "Night owl 🦉" }
        if h < 12 { return "Good morning ☀️" }
        if h < 17 { return "Good afternoon 📚" }
        if h < 21 { return "Good evening 🌙" }
        return "Late night grind 🌃"
    }

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    func generateAISuggestion() {
        guard !AIService.shared.apiKey().isEmpty else {
            aiSuggestion = "Add your Groq API key in Brain → AI Coach to get suggestions."
            return
        }
        loadingAI = true
        aiSuggestion = ""
        let ctx = """
        Today: \(String(format:"%.1f",todayHours))h / \(String(format:"%.0f",todayGoal))h goal
        Streak: \(streak.currentStreak) days
        Pending tasks: \(tasks.tasks.filter{!$0.isCompleted}.count) (\(tasks.tasks.filter{$0.isOverdue}.count) overdue)
        \(nextExam.map { "Next exam: \($0.subject) in \(Int($0.daysUntil)) days" } ?? "No exams soon")
        \(SessionStore.shared.summaryForAI)
        """
        AIService.shared.callPublic(prompt: """
        You are a study coach. Student's situation:
        \(ctx)
        Give ONE short direct actionable suggestion for today (max 2 sentences). Be specific. No fluff.
        """) { result in
            DispatchQueue.main.async { self.aiSuggestion = result; self.loadingAI = false }
        }
    }
}
