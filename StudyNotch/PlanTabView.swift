import SwiftUI
import AppKit

// ── Plan View ─────────────────────────────────────────────────────────────────
//  Tab 3 in the 4-tab structure.
//  Sections: This Week → Tasks → Exams
//  All in one scroll — no nested tabs.

struct PlanTabView: View {
    var tasks     = TaskStore.shared
    var subStore  = SubjectStore.shared
    var sessions  = SessionStore.shared
    var modeStore = ModeStore.shared   // ← ADD: observe mode

    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskSubject = ""
    @State private var newTaskPriority: TaskPriority = .medium
    @State private var newTaskDueDate: Date? = nil
    @State private var showDatePicker = false
    @State private var animateIn = false
    @State private var expandedSection: Set<String> = ["week", "tasks", "exams"]

    var isAcademic: Bool { modeStore.currentMode == .college }

    // Mode-filtered tasks: academic = tasks linked to known college subjects or untagged
    // personal = all tasks (no subject restriction in personal mode)
    var pendingTasks: [StudyTask] {
        let all = tasks.tasks.filter { !$0.isCompleted }
        if isAcademic {
            let academicSubjects = Set(modeStore.collegeSubjects.map { $0.name.lowercased() })
            return all.filter { t in
                t.subject.isEmpty || academicSubjects.contains(t.subject.lowercased())
            }
        }
        return all
    }
    var overdueTasks: [StudyTask] { pendingTasks.filter { $0.isOverdue } }

    // Exams only shown in academic mode
    var upcomingExams: [ExamEntry] {
        guard isAcademic else { return [] }
        return subStore.exams.filter { $0.daysUntil > 0 }.sorted { $0.daysUntil < $1.daysUntil }
    }

    // Weekly subjects: academic = college subjects, personal = all session subjects
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Mode indicator banner
                HStack(spacing: 6) {
                    Image(systemName: isAcademic ? "graduationcap.fill" : "person.fill")
                        .font(.system(size: 10)).foregroundColor(isAcademic ? .blue : .purple)
                    Text(isAcademic ? "Academic Mode — showing college subjects & exams"
                                    : "Personal Mode — showing all personal tasks")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(isAcademic ? Color.blue.opacity(0.05) : Color.purple.opacity(0.05))

                // ── AI Plan Editor Banner ─────────────────────────────────────
                aiPlanBanner

                // This Week section
                sectionHeader("This Week", key: "week", icon: "calendar", color: .blue)
                if expandedSection.contains("week") { weekSection }

                // Tasks section
                sectionHeader("Tasks (\(pendingTasks.count))", key: "tasks", icon: "checklist", color: .green)
                if expandedSection.contains("tasks") { tasksSection }

                // Exams section — academic only
                if isAcademic {
                    sectionHeader("Exams (\(upcomingExams.count))", key: "exams",
                                  icon: "graduationcap.fill", color: .orange)
                    if expandedSection.contains("exams") { examsSection }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { animateIn = true }
        }
    }

    var aiPlanBanner: some View {
        Button {
            AIPlanEditorWindowController.show()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 1.0, blue: 0.55).opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.55))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Plan Editor")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Generate an editable study plan — AI sees all your subjects & tasks")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.55))
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.2, green: 1.0, blue: 0.55).opacity(0.08),
                             Color(red: 0.2, green: 1.0, blue: 0.55).opacity(0.03)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .overlay(Rectangle().frame(height: 1)
                .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.55).opacity(0.15)),
                     alignment: .bottom)
        }
        .buttonStyle(.plain)
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

    // ── This Week ─────────────────────────────────────────────────────────────

    var weekSection: some View {
        let weekActual = sessions.sessions
            .filter { $0.startTime > Date().addingTimeInterval(-7 * 86400) }
            .reduce(0.0) { $0 + $1.duration } / 3600
        let dayActual = sessions.sessions
            .filter { Calendar.current.isDateInToday($0.startTime) }
            .reduce(0.0) { $0 + $1.duration } / 3600
        let weekPct = subStore.globalWeeklyGoalHours > 0
            ? min(1.0, weekActual / subStore.globalWeeklyGoalHours) : 0
        let dayPct  = subStore.globalDailyGoalHours > 0
            ? min(1.0, dayActual  / subStore.globalDailyGoalHours)  : 0
        let accent  = Color(red: 0.2, green: 1.0, blue: 0.55)

        return VStack(spacing: 16) {

            // ── Weekly goal ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Weekly Target", systemImage: "calendar.badge.clock")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1fh / %.0fh this week",
                                weekActual, subStore.globalWeeklyGoalHours))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(weekPct >= 1 ? .green : .secondary)
                }
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.07)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(weekPct >= 1
                                  ? LinearGradient(colors: [Color.green.opacity(0.8), Color.green],
                                                   startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [accent.opacity(0.7), accent],
                                                   startPoint: .leading, endPoint: .trailing))
                            .frame(width: animateIn ? geo.size.width * CGFloat(weekPct) : 0, height: 8)
                            .animation(.easeOut(duration: 0.8), value: animateIn)
                    }
                }
                .frame(height: 8)
                // Stepper
                HStack(spacing: 0) {
                    Button { subStore.globalWeeklyGoalHours = max(1, subStore.globalWeeklyGoalHours - 1); subStore.saveGoals() } label: {
                        Image(systemName: "minus").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 28)
                    }.buttonStyle(.plain)
                    Text(String(format: "%.0f h / week", subStore.globalWeeklyGoalHours))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(accent).frame(minWidth: 100, alignment: .center)
                    Button { subStore.globalWeeklyGoalHours = min(80, subStore.globalWeeklyGoalHours + 1); subStore.saveGoals() } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 32, height: 28)
                    }.buttonStyle(.plain)
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(14)
            .background(accent.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.15), lineWidth: 0.5))

            // ── Daily goal ─────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Daily Target", systemImage: "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1fh / %.0fh today",
                                dayActual, subStore.globalDailyGoalHours))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(dayPct >= 1 ? .green : .secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.07)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(dayPct >= 1
                                  ? LinearGradient(colors: [Color.green.opacity(0.8), Color.green],
                                                   startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [Color.orange.opacity(0.7), Color.orange],
                                                   startPoint: .leading, endPoint: .trailing))
                            .frame(width: animateIn ? geo.size.width * CGFloat(dayPct) : 0, height: 8)
                            .animation(.easeOut(duration: 0.8).delay(0.1), value: animateIn)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 0) {
                    Button { subStore.globalDailyGoalHours = max(0.5, subStore.globalDailyGoalHours - 0.5); subStore.saveGoals() } label: {
                        Image(systemName: "minus").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 28)
                    }.buttonStyle(.plain)
                    Text(String(format: "%.1f h / day", subStore.globalDailyGoalHours))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange).frame(minWidth: 100, alignment: .center)
                    Button { subStore.globalDailyGoalHours = min(24, subStore.globalDailyGoalHours + 0.5); subStore.saveGoals() } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                            .frame(width: 32, height: 28)
                    }.buttonStyle(.plain)
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(14)
            .background(Color.orange.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.15), lineWidth: 0.5))
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    // ── Tasks ─────────────────────────────────────────────────────────────────

    var tasksSection: some View {
        VStack(spacing: 0) {
            // Quick add
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("New task…", text: $newTaskTitle)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        .onSubmit { addTask() }
                    Picker("", selection: $newTaskPriority) {
                        Text("Low").tag(TaskPriority.low)
                        Text("Med").tag(TaskPriority.medium)
                        Text("High").tag(TaskPriority.high)
                    }
                    .pickerStyle(.segmented).frame(width: 130)
                    Button("Add") { addTask() }
                        .buttonStyle(.plain).foregroundColor(.white).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(newTaskTitle.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                        .clipShape(Capsule()).disabled(newTaskTitle.isEmpty)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)

            Divider()

            if pendingTasks.isEmpty {
                Text("All done! No pending tasks.").font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                // Overdue first
                if !overdueTasks.isEmpty {
                    overdueHeader
                    ForEach(overdueTasks) { t in taskRow(t); Divider().padding(.leading, 52) }
                }
                let normal = pendingTasks.filter { !$0.isOverdue }
                ForEach(normal) { t in taskRow(t); Divider().padding(.leading, 52) }
            }

            // Completed (collapsed count)
            let done = tasks.tasks.filter { $0.isCompleted }
            if !done.isEmpty {
                Text("✓ \(done.count) completed")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.vertical, 8).frame(maxWidth: .infinity)
            }
        }
    }

    var overdueHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 10))
            Text("OVERDUE").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
        }
        .padding(.horizontal, 24).padding(.vertical, 4)
        .background(Color.red.opacity(0.06))
    }

    func taskRow(_ t: StudyTask) -> some View {
        HStack(spacing: 12) {
            Button { tasks.complete(t) } label: {
                Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(t.isCompleted ? .green : t.isOverdue ? .red : .white.opacity(0.35))
            }.buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(t.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    priorityBadge(t.priority)
                }
                HStack(spacing: 6) {
                    if !t.subject.isEmpty {
                        Circle().fill(SubjectStore.shared.color(for: t.subject)).frame(width: 6, height: 6)
                        Text(t.subject).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    if let d = t.dueDate {
                        Text(d.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 10))
                            .foregroundColor(t.isOverdue ? .red : t.dueSoon ? .orange : .secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 9)
    }

    func priorityBadge(_ p: TaskPriority) -> some View {
        let color: Color = p == .high ? .red : p == .medium ? .orange : .secondary
        return Text(p.rawValue.prefix(1).uppercased())
            .font(.system(size: 8, weight: .bold)).foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    func addTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let task = StudyTask(title: trimmed,
                             subject: newTaskSubject,
                             priority: newTaskPriority,
                             dueDate: newTaskDueDate)
        tasks.add(task)
        newTaskTitle = ""
    }

    // ── Exams ─────────────────────────────────────────────────────────────────

    var examsSection: some View {
        VStack(spacing: 10) {
            if upcomingExams.isEmpty {
                Text("No upcoming exams — add them in Study Plan.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(upcomingExams) { exam in
                    examRow(exam)
                }
            }
            Button("Manage Exams in Study Plan →") { StudyPlanWindowController.show(tab: 2) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.accentColor)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    func examRow(_ e: ExamEntry) -> some View {
        let days = Int(e.daysUntil)
        let c: Color = days <= 2 ? .red : days <= 7 ? .orange : .blue
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(c.opacity(0.2), lineWidth: 3).frame(width: 44, height: 44)
                VStack(spacing: 0) {
                    Text("\(days)").font(.system(size: 14, weight: .bold)).foregroundColor(c)
                    Text("days").font(.system(size: 7)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.subject).font(.system(size: 13, weight: .semibold))
                Text(e.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if !e.location.isEmpty {
                    Label(e.location, systemImage: "mappin.circle")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Spacer()
            if days <= 3 {
                Text(days == 0 ? "TODAY" : days == 1 ? "TOMORROW" : "\(days) DAYS")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(c)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(c.opacity(0.12)).clipShape(Capsule())
            }
        }
        .padding(12)
        .background(c.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.opacity(0.15), lineWidth: 0.5))
    }
}
