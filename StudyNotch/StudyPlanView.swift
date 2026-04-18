import SwiftUI

// ── Study Plan / Schedule Window ─────────────────────────────────────────────

struct StudyPlanView: View {
    @Bindable var subjectStore = SubjectStore.shared
    @Bindable var sessionStore = SessionStore.shared
    var modeStore    = ModeStore.shared
    var taskStore    = TaskStore.shared

    @State private var selectedSubject: String? = nil
    var initialTab: Int = 0
    @State private var selectedTab = 0   // 0=Heatmap 1=Plan 2=Exams 3=Tasks 4=Notifications 5=Forest 6=Sky

    var subjects: [String] {
        // Always start with session history so subjects with actual data always appear
        var all: [String] = sessionStore.knownSubjects
        // Merge in college subjects (may have been added without sessions yet)
        for s in modeStore.collegeSubjects.map(\.name) {
            if !all.contains(s) { all.append(s) }
        }
        // Ensure SubjectStore has metas for all
        for s in all { subjectStore.ensureMeta(for: s) }
        return all
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top bar ───────────────────────────────────────────────────────
            HStack(spacing: 0) {
                let tabs = ["Heatmap", "Weekly Plan", "Exams", "Tasks", "Notifications", "Forest", "Sky"]
                ForEach(tabs, id: \.self) { tab in
                    let idx = tabs.firstIndex(of: tab)!
                    Button {
                        withAnimation { selectedTab = idx }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab)
                                .font(.system(size: 12, weight: selectedTab == idx ? .semibold : .regular))
                                .foregroundColor(selectedTab == idx ? .white : .white.opacity(0.4))
                            // Badge for Tasks tab
                            if tab == "Tasks" && taskStore.pendingCount > 0 {
                                Text("\(taskStore.pendingCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(taskStore.overdueCount > 0 ? Color.red : Color.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                // Subject filter
                Menu {
                    Button("All Subjects") { selectedSubject = nil }
                    Divider()
                    ForEach(subjects, id: \.self) { s in
                        Button(s) { selectedSubject = s }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let s = selectedSubject {
                            Circle().fill(subjectStore.color(for: s)).frame(width: 7, height: 7)
                        }
                        Text(selectedSubject ?? "All")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.07)).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
            .background(Color.white.opacity(0.03))

            Divider().overlay(Color.white.opacity(0.07))

            // ── Content ───────────────────────────────────────────────────────
            Group {
                if selectedTab == 0 { heatmapTab }
                else if selectedTab == 1 { weeklyPlanTab }
                else if selectedTab == 2 { examsTab }
                else if selectedTab == 3 { TasksTab(subjectFilter: selectedSubject) }
                else if selectedTab == 4 { notificationsTab }
                else if selectedTab == 5 { StudyForestView() }
                else if selectedTab == 6 { ConstellationMapView() }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { if initialTab != 0 { selectedTab = initialTab } }
    }

    // ── Heatmap ───────────────────────────────────────────────────────────────

    var heatmapTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Study Activity — Last 35 days")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 18).padding(.horizontal, 20)

                let data = subjectStore.heatmapData(
                    subject: selectedSubject,
                    sessions: sessionStore.sessions,
                    days: 35
                )
                HeatmapGrid(days: data, subject: selectedSubject)
                    .padding(.horizontal, 20)

                // Per-subject actual vs planned bars
                if selectedSubject == nil {
                    Text("This Week — Planned vs Actual")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20).padding(.top, 8)

                    ForEach(subjects, id: \.self) { sub in
                        let actual  = subjectStore.actualHoursThisWeek(subject: sub, sessions: sessionStore.sessions)
                        let planned = subjectStore.weeklyGoals.first { $0.subject == sub }?.weeklyHours ?? 0
                        PlannedVsActualBar(subject: sub, actual: actual, planned: planned)
                            .padding(.horizontal, 20)
                    }
                }
                Spacer(minLength: 20)
            }
        }
    }

    // ── Weekly Plan ───────────────────────────────────────────────────────────

    var weeklyPlanTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {

                // ── Legend ────────────────────────────────────────────────
                HStack(spacing: 16) {
                    Text("Set weekly & daily targets per subject")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("Not studied yet").font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("On track").font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                    }
                }
                .padding(.top, 18).padding(.horizontal, 20)

                // ── Global daily goal ─────────────────────────────────────
                HStack(spacing: 12) {
                    Text("Global daily goal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 140, alignment: .leading)
                    Slider(value: $subjectStore.globalDailyGoalHours, in: 0.5...12, step: 0.5)
                        .frame(width: 180)
                        .onChange(of: subjectStore.globalDailyGoalHours) { _ in subjectStore.saveGoals() }
                    Text(String(format: "%.1f h/day", subjectStore.globalDailyGoalHours))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Picker("Mode", selection: $subjectStore.dailyGoalMode) {
                        ForEach(DailyGoalMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: subjectStore.dailyGoalMode) { _ in subjectStore.saveGoals() }
                }
                .padding(.horizontal, 20).padding(.top, 10)

                Divider().overlay(Color.white.opacity(0.07)).padding(.vertical, 6).padding(.horizontal, 20)

                // ── All subjects — always shown, even with zero sessions ───
                // allPlanSubjects merges sessions, college subjects, and subject metas
                let allPlan = allPlanSubjects
                if allPlan.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 28)).foregroundColor(.white.opacity(0.15))
                        Text("No subjects yet")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.35))
                        Text("Add subjects in Analytics → Subjects, or log a session.")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.2))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(allPlan, id: \.self) { sub in
                        SubjectGoalRow(subject: sub)
                            .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 20)
            }
        }
    }

    /// All subjects visible in the plan — sessions + college subjects + meta subjects, deduplicated
    var allPlanSubjects: [String] {
        var seen  = Set<String>()
        var all   : [String] = []
        let lists : [[String]] = [
            sessionStore.knownSubjects,
            modeStore.collegeSubjects.map(\.name),
            subjectStore.metas.map(\.name)
        ]
        for list in lists {
            for s in list where !s.isEmpty {
                if seen.insert(s).inserted { all.append(s) }
            }
        }
        for s in all { subjectStore.ensureMeta(for: s) }
        return all
    }

    // ── Exams ─────────────────────────────────────────────────────────────────

    var examsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExamListView()
        }
    }

    var notificationsTab: some View {
        NotificationsTabView()
    }
}

// ── Heatmap Grid ──────────────────────────────────────────────────────────────

struct HeatmapGrid: View {
    let days   : [HeatmapDay]
    let subject: String?

    var maxHours: Double { days.map(\.hours).max() ?? 1.0 }

    var body: some View {
        let cols = 7
        let rows = (days.count + cols - 1) / cols
        let cellSize: CGFloat = 24
        let spacing : CGFloat = 4

        VStack(alignment: .leading, spacing: spacing) {
            // Day labels
            HStack(spacing: spacing) {
                ForEach(["S","M","T","W","T","F","S"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: cellSize, height: 14, alignment: .center)
                }
            }
            // Cells
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < days.count {
                            let day = days[idx]
                            HeatCell(hours: day.hours, maxHours: maxHours, subject: subject)
                                .frame(width: cellSize, height: cellSize)
                        } else {
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
}

struct HeatCell: View {
    let hours   : Double
    let maxHours: Double
    let subject : String?

    var intensity: Double { maxHours > 0 ? min(hours / maxHours, 1.0) : 0 }
    var baseColor: Color {
        if let s = subject { return SubjectStore.shared.color(for: s) }
        return Color(red: 0.2, green: 1.0, blue: 0.5)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(hours == 0
                ? Color.white.opacity(0.06)
                : baseColor.opacity(0.15 + intensity * 0.85))
            .overlay {
                if hours > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(baseColor.opacity(intensity * 0.5), lineWidth: 0.5)
                }
            }
    }
}

// ── Planned vs Actual Bar ─────────────────────────────────────────────────────

struct PlannedVsActualBar: View {
    let subject : String
    let actual  : Double
    let planned : Double

    var body: some View {
        let max   = Swift.max(actual, planned, 0.5)
        let color = SubjectStore.shared.color(for: subject)
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(subject)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 90, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    // planned (ghost)
                    Capsule().fill(Color.white.opacity(0.09)).frame(height: 8)
                    if planned > 0 {
                        Capsule().fill(color.opacity(0.25))
                            .frame(width: g.size.width * CGFloat(planned / max), height: 8)
                    }
                    // actual (solid)
                    Capsule().fill(color)
                        .frame(width: g.size.width * CGFloat(actual / max), height: 5)
                        .offset(y: 1.5)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f / %.1f h", actual, planned))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 72, alignment: .trailing)
        }
        .frame(height: 28)
    }
}

// ── Subject Goal Row ──────────────────────────────────────────────────────────

struct SubjectGoalRow: View {
    var store     = SubjectStore.shared
    var sessions  = SessionStore.shared
    @Bindable var taskStore = TaskStore.shared
    let subject: String

    var weeklyGoal  : Double { store.weeklyGoals.first { $0.subject == subject }?.weeklyHours ?? 0 }
    var dailyGoal   : Double { store.subjectDailyGoals[subject] ?? store.globalDailyGoalHours }
    var actualWeek  : Double { store.actualHoursThisWeek(subject: subject, sessions: sessions.sessions) }
    var actualToday : Double {
        sessions.sessions
            .filter { Calendar.current.isDateInToday($0.date) && $0.subject == subject }
            .reduce(0) { $0 + $1.duration } / 3600
    }
    var totalEver   : Double {
        sessions.sessions.filter { $0.subject == subject }.reduce(0) { $0 + $1.duration }
    }
    var pendingTasks: Int { taskStore.tasks.filter {  $0.subject == subject && !$0.isCompleted }.count }
    var overdueTasks: Int { taskStore.tasks.filter {  $0.subject == subject && !$0.isCompleted && $0.isOverdue }.count }
    var isUntouched : Bool { totalEver == 0 }

    @State private var weeklyInput: Double = 0
    @State private var dailyInput : Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            weeklyRow
            dailyRow
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(isUntouched ? Color.orange.opacity(0.06) : Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isUntouched ? Color.orange.opacity(0.25) : Color.clear, lineWidth: 1))
        .onAppear { weeklyInput = weeklyGoal; dailyInput = dailyGoal }
        .onChange(of: store.weeklyGoals.count)       { _ in weeklyInput = weeklyGoal }
        .onChange(of: store.subjectDailyGoals.count) { _ in dailyInput  = dailyGoal }
    }

    // ── Header ─────────────────────────────────────────────────────────────

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle().fill(store.color(for: subject))
                .frame(width: 9, height: 9)
                .shadow(color: store.color(for: subject).opacity(0.7), radius: 3)

            Text(subject)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            badgeRow

            Spacer()

            // Today ring
            HStack(spacing: 4) {
                GoalRing(
                    progress : dailyGoal > 0 ? min(actualToday / dailyGoal, 1.0) : 0,
                    color    : store.color(for: subject),
                    size     : 22,
                    lineWidth: 3
                )
                Text(String(format: "%.1fh today", actualToday))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isUntouched ? .orange.opacity(0.7) : .white.opacity(0.4))
            }
        }
    }

    // ── Status badges (broken out to avoid type-checker timeout) ───────────

    @ViewBuilder
    private var badgeRow: some View {
        if isUntouched {
            Text("NOT STUDIED YET")
                .font(.system(size: 8, weight: .bold)).foregroundColor(.black)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.orange).clipShape(Capsule())
        }
        examBadge
        taskBadge
    }

    @ViewBuilder
    private var examBadge: some View {
        if let exam = store.exams
            .filter({ $0.subject == subject })
            .sorted(by: { $0.daysUntil < $1.daysUntil })
            .first, exam.daysUntil > 0 {
            let d = Int(exam.daysUntil)
            Text("Exam \(d)d")
                .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(d <= 3 ? Color.red : d <= 7 ? Color.orange : Color.blue.opacity(0.7))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var taskBadge: some View {
        if pendingTasks > 0 {
            HStack(spacing: 2) {
                Image(systemName: overdueTasks > 0 ? "exclamationmark.circle.fill" : "checklist")
                    .font(.system(size: 8))
                Text("\(pendingTasks)").font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(overdueTasks > 0 ? .red : .white.opacity(0.5))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background((overdueTasks > 0 ? Color.red : Color.white).opacity(0.12))
            .clipShape(Capsule())
        }
    }

    // ── Weekly slider ───────────────────────────────────────────────────────

    private var weeklyRow: some View {
        HStack(spacing: 8) {
            Text("Weekly")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                .frame(width: 44, alignment: .leading)
            Slider(value: $weeklyInput, in: 0...40, step: 0.5)
                .onChange(of: weeklyInput) { val in store.setWeeklyGoal(subject: subject, hours: val) }
            Text(String(format: "%.0fh", weeklyInput))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(store.color(for: subject))
                .frame(width: 28, alignment: .trailing)
            Text(String(format: "/ %.1fh done", actualWeek))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(actualWeek >= weeklyGoal && weeklyGoal > 0 ? .green
                                 : isUntouched ? .orange.opacity(0.6) : .white.opacity(0.3))
                .frame(width: 72, alignment: .leading)
        }
    }

    // ── Daily row (global = read-only bar, per-subject = slider) ───────────

    @ViewBuilder
    private var dailyRow: some View {
        if store.dailyGoalMode == .global {
            dailyGlobalRow
        } else {
            dailySliderRow
        }
    }

    private var dailyGlobalRow: some View {
        HStack(spacing: 8) {
            Text("Daily")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                .frame(width: 44, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule().fill(store.color(for: subject))
                        .frame(width: g.size.width * CGFloat(min(actualToday / max(dailyGoal, 0.01), 1.0)),
                               height: 4)
                }
            }
            .frame(height: 4)
            Text(String(format: "%.1fh / %.1fh", actualToday, dailyGoal))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(actualToday >= dailyGoal ? .green : .white.opacity(0.4))
            Text("(global)").font(.system(size: 9)).foregroundColor(.white.opacity(0.2))
        }
    }

    private var dailySliderRow: some View {
        HStack(spacing: 8) {
            Text("Daily")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                .frame(width: 44, alignment: .leading)
            Slider(value: $dailyInput, in: 0.5...12, step: 0.5)
                .onChange(of: dailyInput) { val in
                    store.subjectDailyGoals[subject] = val
                    store.saveGoals()
                }
            Text(String(format: "%.1fh", dailyInput))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(store.color(for: subject))
                .frame(width: 32, alignment: .trailing)
            Text(String(format: "/ %.1fh done", actualToday))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(actualToday >= dailyInput ? .green : .white.opacity(0.3))
                .frame(width: 78, alignment: .leading)
        }
    }
}

// ── Exam List View ────────────────────────────────────────────────────────────

struct ExamListView: View {
    var store  = SubjectStore.shared
    @Bindable var mStore = ModeStore.shared
    @State private var showAdd = false
    @State private var editExam: ExamEntry?

    var subjects: [String] {
        mStore.currentMode == .college
            ? mStore.collegeSubjects.map(\.name)
            : SessionStore.shared.knownSubjects
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Exam Countdown")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Button { showAdd = true } label: {
                    Label("Add Exam", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider().overlay(Color.white.opacity(0.07))

            if store.exams.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No exams scheduled")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.exams.sorted { $0.daysUntil < $1.daysUntil }) { exam in
                        ExamRow(exam: exam) { editExam = exam }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $showAdd) {
            ExamEditSheet(exam: nil, subjects: subjects) { newExam in
                store.addExam(newExam)
            }
        }
        .sheet(item: $editExam) { exam in
            ExamEditSheet(exam: exam, subjects: subjects) { updated in
                store.updateExam(updated)
            }
        }
    }
}

struct ExamRow: View {
    @Bindable var store = SubjectStore.shared
    let exam   : ExamEntry
    let onEdit : () -> Void

    var urgencyColor: Color {
        let d = exam.daysUntil
        if d < 1 { return .red }
        if d < 3 { return .orange }
        return Color(red: 0.2, green: 1.0, blue: 0.5)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color dot
            Circle().fill(store.color(for: exam.subject)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.subject)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                if !exam.notes.isEmpty {
                    Text(exam.notes).font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                }
            }
            Spacer()
            Text(exam.date.formatted(.dateTime.month().day().year()))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            // Countdown pill
            if exam.daysUntil > 0 {
                Text(exam.pillText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(urgencyColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(urgencyColor.opacity(0.15)).clipShape(Capsule())
            } else {
                Text("Passed").font(.system(size: 10)).foregroundColor(.white.opacity(0.2))
            }
            Button { onEdit() } label: {
                Image(systemName: "pencil").font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            Button { store.deleteExam(exam) } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8).padding(.horizontal, 20)
    }
}

struct ExamEditSheet: View {
    @Environment(\.dismiss) var dismiss
    let exam     : ExamEntry?
    let subjects : [String]
    let onSave   : (ExamEntry) -> Void

    @State private var subject = ""
    @State private var date    = Date().addingTimeInterval(7*86400)
    @State private var notes   = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exam == nil ? "Add Exam" : "Edit Exam")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text("Subject").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                Picker("Subject", selection: $subject) {
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Exam Date").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .frame(maxWidth: 260)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (optional)").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                TextField("Chapter 1-5, hall B...", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Button("Save") {
                    var e = exam ?? ExamEntry(subject: subject.isEmpty ? (subjects.first ?? "—") : subject, date: date)
                    e.subject = subject.isEmpty ? (subjects.first ?? "—") : subject
                    e.date    = date
                    e.notes   = notes
                    onSave(e); dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.5))
                .font(.system(size: 12, weight: .bold))
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
        .onAppear {
            if let e = exam {
                subject = e.subject; date = e.date; notes = e.notes
            } else {
                subject = subjects.first ?? ""
            }
        }
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────


// ── Notifications Tab helper (used by StudyPlanView body) ─────────────────────

struct NotificationsTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 18)).foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.system(size: 16, weight: .bold))
                        Text("Smart reminders so you never miss a study day or exam")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)

                // iPhone push (ntfy.sh)
                IPhoneNotificationSection()

                // Mac notifications
                NotificationSettingsSection()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Tasks Tab ─────────────────────────────────────────────────────────────────

struct TasksTab: View {
    var taskStore    = TaskStore.shared
    @Bindable var subjectStore = SubjectStore.shared
    let subjectFilter: String?

    @State private var showAdd        = false
    @State private var editTask       : StudyTask?
    @State private var showCompleted  = false

    var pending  : [StudyTask] { taskStore.pending(for: subjectFilter) }
    var completed: [StudyTask] { taskStore.completed(for: subjectFilter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Study Tasks")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        if taskStore.overdueCount > 0 {
                            Label("\(taskStore.overdueCount) overdue",
                                  systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        Text("\(pending.count) pending")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                        Text("\(completed.count) done")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.6))
                    }
                }
                Spacer()
                Button {
                    showAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("Add Task").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(red: 0.2, green: 1.0, blue: 0.5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider().overlay(Color.white.opacity(0.07))

            if pending.isEmpty && completed.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No tasks yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Add tasks to track what you need to study.\nCompleting tasks earns XP!")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        
                        // ── Due for Recall ────────────────────────────────────
                        let srDue = taskStore.dueSRTasks().filter { subjectFilter == nil || $0.subject == subjectFilter }
                        if !srDue.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "brain.head.profile").foregroundColor(.accentColor)
                                    Text("Ready for Review").font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    Text("\(srDue.count)").font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.2)).clipShape(Capsule())
                                }
                                .padding(.horizontal, 20).padding(.top, 16)
                                
                                ForEach(srDue) { task in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title).font(.system(size: 12, weight: .semibold))
                                            Text("Interval: \(fmtSR(task.srInterval))").font(.system(size: 10)).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        HStack(spacing: 8) {
                                            Button { taskStore.recordSRRecall(id: task.id, success: false) } label: {
                                                Image(systemName: "xmark.circle").foregroundColor(.red.opacity(0.8))
                                            }.buttonStyle(.plain)
                                            Button { taskStore.recordSRRecall(id: task.id, success: true) } label: {
                                                Text("I Remember").font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(Color.green).clipShape(Capsule())
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.accentColor.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal, 20)
                                }
                                
                                Divider().overlay(Color.white.opacity(0.07)).padding(.top, 8)
                            }
                        }

                        // ── Pending tasks ─────────────────────────────────────
                        if !pending.isEmpty {
                            ForEach(pending) { task in
                                TaskRow(task: task) { editTask = task }
                                Divider().overlay(Color.white.opacity(0.05))
                            }
                        }

                        // ── Completed toggle ──────────────────────────────────
                        if !completed.isEmpty {
                            Button {
                                withAnimation { showCompleted.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9))
                                    Text("\(completed.count) completed")
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                }
                                .foregroundColor(.white.opacity(0.3))
                                .padding(.horizontal, 20).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if showCompleted {
                                ForEach(completed.prefix(20)) { task in
                                    TaskRow(task: task) { editTask = task }
                                        .opacity(0.5)
                                    Divider().overlay(Color.white.opacity(0.04))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            TaskEditSheet(task: nil)
        }
        .sheet(item: $editTask) { t in
            TaskEditSheet(task: t)
        }
    }

    func fmtSR(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86400)
        if days == 0 { return "New" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}

// ── Task Row ──────────────────────────────────────────────────────────────────

struct TaskRow: View {
    var taskStore    = TaskStore.shared
    @Bindable var subjectStore = SubjectStore.shared
    let task  : StudyTask
    let onEdit: () -> Void

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {

                // ── Checkbox ──────────────────────────────────────────────
                Button {
                    if task.isCompleted { taskStore.uncomplete(task) }
                    else                { taskStore.complete(task)   }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(task.isCompleted ? .green
                                         : task.isOverdue ? .red : .white.opacity(0.4))
                }
                .buttonStyle(.plain)

                // ── Content ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {

                    // Title row
                    HStack(spacing: 6) {
                        // Task-type icon badge
                        if task.taskType != .general {
                            Image(systemName: task.taskType.icon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(typeColor)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(typeColor.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(task.isCompleted ? .white.opacity(0.35) : .white.opacity(0.9))
                            .strikethrough(task.isCompleted)
                            .lineLimit(2)

                        if !task.isCompleted {
                            Image(systemName: task.priority.icon)
                                .font(.system(size: 9)).foregroundColor(priorityColor)
                            Text("+\(task.priority.xpReward)XP")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.yellow.opacity(0.6))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.1)).clipShape(Capsule())
                        }
                    }

                    // Meta row
                    HStack(spacing: 8) {
                        if !task.subject.isEmpty {
                            HStack(spacing: 3) {
                                Circle().fill(subjectStore.color(for: task.subject)).frame(width: 5, height: 5)
                                Text(task.subject).font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                            }
                        }
                        if let d = task.dueDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar").font(.system(size: 9))
                                Text(fmt.string(from: d)).font(.system(size: 10))
                            }
                            .foregroundColor(task.isOverdue ? .red : task.dueSoon ? .orange : .white.opacity(0.35))
                        }
                        // Progress label for typed tasks
                        if task.taskType.hasProgress && task.taskTotal > 0 {
                            Text("\(task.taskDone)/\(task.taskTotal) \(task.taskType.unit)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(typeColor.opacity(0.8))
                        }
                        if !task.notes.isEmpty {
                            Text(task.notes).font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.25)).lineLimit(1)
                        }
                    }

                    // Progress bar + stepper for typed tasks
                    if task.taskType.hasProgress && task.taskTotal > 0 && !task.isCompleted {
                        HStack(spacing: 8) {
                            // Bar
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                                    Capsule().fill(typeColor)
                                        .frame(width: g.size.width * CGFloat(task.taskProgress), height: 4)
                                }
                            }
                            .frame(height: 4)

                            // Inline – / + stepper
                            HStack(spacing: 0) {
                                Button {
                                    taskStore.updateProgress(id: task.id, done: task.taskDone - 1)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                        .frame(width: 20, height: 18)
                                }
                                .buttonStyle(.plain)
                                .disabled(task.taskDone <= 0)

                                Button {
                                    taskStore.updateProgress(id: task.id, done: task.taskDone + 1)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(typeColor)
                                        .frame(width: 20, height: 18)
                                }
                                .buttonStyle(.plain)
                                .disabled(task.taskDone >= task.taskTotal)
                            }
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }

                Spacer()

                // ── Edit / duplicate / delete ─────────────────────────────
                HStack(spacing: 6) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.25)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Edit task")

                    Button { taskStore.duplicate(task) } label: {
                        Image(systemName: "plus.square.on.square").font(.system(size: 11))
                            .foregroundColor(.blue.opacity(0.5)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Duplicate task")

                    Button { taskStore.delete(task) } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.3)).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Delete task")
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(task.isOverdue && !task.isCompleted ? Color.red.opacity(0.04) : Color.clear)
    }

    var typeColor: Color {
        switch task.taskType {
        case .general:    return .white.opacity(0.5)
        case .video:      return Color(red: 0.85, green: 0.35, blue: 1.00)
        case .lecture:    return Color(red: 0.20, green: 0.78, blue: 1.00)
        case .assignment: return Color(red: 1.00, green: 0.55, blue: 0.20)
        case .sheet:      return Color(red: 0.35, green: 1.00, blue: 0.55)
        }
    }

    var priorityColor: Color {
        switch task.priority {
        case .low:    return .white.opacity(0.3)
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

// ── Task Edit Sheet ───────────────────────────────────────────────────────────

struct TaskEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var taskStore = TaskStore.shared
    var sessions  = SessionStore.shared
    @Bindable var modeStore = ModeStore.shared
    let task: StudyTask?

    @State private var title     = ""
    @State private var subject   = ""
    @State private var priority  : TaskPriority  = .medium
    @State private var taskType  : TaskTypeKind  = .general
    @State private var taskTotal : String        = ""   // string for TextField
    @State private var taskDone  : String        = "0"
    @State private var hasDue    = false
    @State private var dueDate   = Date().addingTimeInterval(86400)
    @State private var notes     = ""
    @State private var isSR      = false

    var subjects: [String] {
        var s = sessions.knownSubjects
        if modeStore.currentMode == .college {
            for sub in modeStore.collegeSubjects.map(\.name) {
                if !s.contains(sub) { s.append(sub) }
            }
        }
        return s
    }

    var isEditing: Bool { task != nil }

    // Dynamic sheet height — taller when type has progress fields or SR enabled
    var sheetHeight: CGFloat {
        var h: CGFloat = taskType.hasProgress ? 620 : 540
        if isSR { h += 60 }
        return h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.07))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Task title ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Task", icon: "checkmark.circle")
                        TextField("e.g. Watch lecture 3 — Data Structures", text: $title)
                            .textFieldStyle(.roundedBorder).font(.system(size: 13))
                    }

                    // ── Task type ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Type", icon: "square.grid.2x2")
                        HStack(spacing: 6) {
                            ForEach(TaskTypeKind.allCases, id: \.self) { kind in
                                Button { withAnimation(.easeOut(duration: 0.2)) { taskType = kind } } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: kind.icon).font(.system(size: 10))
                                        Text(kind.rawValue).font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(taskType == kind ? .black : typeColor(kind))
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(taskType == kind
                                                ? typeColor(kind)
                                                : typeColor(kind).opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .animation(.easeOut(duration: 0.15), value: taskType)
                    }

                    // ── Type-specific progress fields ─────────────────────
                    if taskType.hasProgress {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldLabel("Progress tracking", icon: "chart.bar.fill")

                            HStack(spacing: 12) {
                                // Total
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(taskType.totalLabel)
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                    TextField("0", text: $taskTotal)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13, design: .monospaced))
                                        .frame(width: 90)
                                }
                                // Done
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(taskType.doneLabel)
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                    TextField("0", text: $taskDone)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13, design: .monospaced))
                                        .frame(width: 90)
                                }
                                Spacer()
                                // Live progress pill
                                let total = Int(taskTotal) ?? 0
                                let done  = Int(taskDone)  ?? 0
                                if total > 0 {
                                    let pct = min(100, Int(Double(done) / Double(total) * 100))
                                    Text("\(pct)%")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(typeColor(taskType))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(typeColor(taskType).opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }

                            // Mini preview bar
                            let total = max(1, Int(taskTotal) ?? 1)
                            let done  = min(total, Int(taskDone) ?? 0)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                                    Capsule().fill(typeColor(taskType))
                                        .frame(width: g.size.width * CGFloat(done) / CGFloat(total), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(12)
                        .background(typeColor(taskType).opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(typeColor(taskType).opacity(0.2), lineWidth: 0.5))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // ── Subject ───────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Subject (optional)", icon: "book.fill")
                        Picker("Subject", selection: $subject) {
                            Text("None").tag("")
                            ForEach(subjects, id: \.self) { s in Text(s).tag(s) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }

                    // ── Priority ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Priority", icon: "flag.fill")
                        HStack(spacing: 8) {
                            ForEach(TaskPriority.allCases, id: \.self) { p in
                                Button { priority = p } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: p.icon).font(.system(size: 10))
                                        Text(p.rawValue).font(.system(size: 11, weight: .medium))
                                        Text("+\(p.xpReward)XP").font(.system(size: 9)).opacity(0.6)
                                    }
                                    .foregroundColor(priority == p ? .black : priorityColor(p))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(priority == p ? priorityColor(p) : priorityColor(p).opacity(0.1))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // ── Due date ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            fieldLabel("Due date", icon: "calendar")
                            Spacer()
                            Toggle("", isOn: $hasDue).labelsHidden()
                        }
                        if hasDue {
                            DatePicker("", selection: $dueDate, displayedComponents: [.date])
                                .labelsHidden().datePickerStyle(.compact)
                        }
                    }

                    // ── Notes ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Notes", icon: "note.text")
                        TextField("Optional details…", text: $notes)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    }

                    // ── Spaced Repetition ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            fieldLabel("Spaced Repetition", icon: "brain")
                            Spacer()
                            Toggle("", isOn: $isSR).labelsHidden()
                        }
                        if isSR {
                            Text("Automatic 1d → 3d → 7d... recall scheduling + notifications.")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor.opacity(0.8))
                                .padding(.leading, 18)
                        }
                    }
                    .padding(12)
                    .background(isSR ? Color.accentColor.opacity(0.06) : Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }

            Divider().overlay(Color.white.opacity(0.07))

            // ── Action buttons ────────────────────────────────────────────
            HStack(spacing: 12) {
                if isEditing {
                    Button("Delete") {
                        if let t = task { taskStore.delete(t) }
                        dismiss()
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.red.opacity(0.6))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.4)).font(.system(size: 12))
                Button(isEditing ? "Save" : "Add Task") { saveTask() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(title.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? .white.opacity(0.3)
                                     : Color(red: 0.2, green: 1.0, blue: 0.5))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420)
        .frame(minHeight: sheetHeight)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .animation(.easeOut(duration: 0.2), value: taskType)
        .onAppear {
            guard let t = task else { return }
            title     = t.title
            subject   = t.subject
            priority  = t.priority
            taskType  = t.taskType
            taskTotal = t.taskTotal > 0 ? "\(t.taskTotal)" : ""
            taskDone  = "\(t.taskDone)"
            dueDate   = t.dueDate ?? Date().addingTimeInterval(86400)
            notes     = t.notes
            isSR      = t.isSR
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    func fieldLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(.accentColor)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
        }
    }

    func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .low:    return .white.opacity(0.5)
        case .medium: return .orange
        case .high:   return .red
        }
    }

    func typeColor(_ k: TaskTypeKind) -> Color {
        switch k {
        case .general:    return .white.opacity(0.5)
        case .video:      return Color(red: 0.85, green: 0.35, blue: 1.00)
        case .lecture:    return Color(red: 0.20, green: 0.78, blue: 1.00)
        case .assignment: return Color(red: 1.00, green: 0.55, blue: 0.20)
        case .sheet:      return Color(red: 0.35, green: 1.00, blue: 0.55)
        }
    }

    func fmtSR(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86400)
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        if days < 30 { return "\(days) days" }
        return "\(days / 30) months"
    }

    func saveTask() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let total = Int(taskTotal) ?? 0
        let done  = min(total, Int(taskDone) ?? 0)
        if var t = task {
            t.title     = trimmed
            t.subject   = subject
            t.priority  = priority
            t.taskType  = taskType
            t.taskTotal = total
            t.taskDone  = done
            t.dueDate   = hasDue ? dueDate : nil
            t.notes     = notes
            t.isSR      = isSR
            if isSR && t.nextRecall == nil { t.nextRecall = Date().addingTimeInterval(86400) }
            taskStore.update(t)
        } else {
            let t = StudyTask(
                title    : trimmed,
                subject  : subject,
                priority : priority,
                dueDate  : hasDue ? dueDate : nil,
                notes    : notes,
                taskType : taskType,
                taskTotal: total,
                taskDone : done,
                isSR     : isSR,
                nextRecall: isSR ? Date().addingTimeInterval(86400) : nil
            )
            taskStore.add(t)
        }
        dismiss()
    }
}

class StudyPlanWindowController: NSWindowController {
    static var shared: StudyPlanWindowController?

    static func show(tab: Int = 0) {
        if shared == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            win.title = "Study Plan"
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 620, height: 420)
            win.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            win.contentView = NSHostingView(rootView: StudyPlanView(initialTab: tab))
            win.center()
            shared = StudyPlanWindowController(window: win)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
                shared = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showTasks() { show(tab: 3) }
}
