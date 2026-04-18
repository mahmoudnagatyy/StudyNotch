import SwiftUI
import AppKit
import Charts

struct AnalyticsView: View {
    var store     = SessionStore.shared
    @Bindable var modeStore = ModeStore.shared
    var ai        = AIService.shared
    @State private var tab        = 0  // 0=Today 1=Progress 2=Plan 3=Brain
    @State private var showSubjectsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            Group {
                switch tab {
                case 0:  TodayView()
                case 2:  PlanTabView()
                case 3:  BrainTabView()
                default: ProgressTabView() // case 1
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSubjectsSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text(isCollege ? "College Subjects" : "Personal Subjects").font(.system(size: 16, weight: .bold))
                    Spacer()
                    Button("Done") { showSubjectsSheet = false }.buttonStyle(.borderedProminent)
                }.padding(.horizontal, 20).padding(.vertical, 16)
                Divider()
                if isCollege { collegeModeTab } else { personalModeTab }
            }.frame(width: 500, height: 600)
        }
    }

    var isCollege: Bool { modeStore.currentMode == .college }

    // ── 5-Tab bar ─────────────────────────────────────────────────────────────

    var tabBar: some View {
        HStack(spacing: 0) {
            tabBtn("Today",    "sun.max.fill",         0)
            tabBtn("Progress", "chart.bar.fill",       1)
            tabBtn("Plan",     "calendar.badge.clock", 2)
            tabBtn("Brain",    "brain.head.profile",   3)
        }
        .padding(.horizontal, 20).padding(.vertical, 4)
    }

    func tabBtn(_ label: String, _ icon: String, _ idx: Int) -> some View {
        let sel = tab == idx
        return Button { withAnimation(.easeOut(duration: 0.15)) { tab = idx } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: sel ? .semibold : .regular))
            }
            .foregroundColor(sel ? .accentColor : .secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if sel {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor)
                        .frame(height: 2).padding(.horizontal, 12).transition(.scale)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // ── Header ────────────────────────────────────────────────────────────────

    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Study Analytics").font(.system(size: 20, weight: .bold))
                Text("\(store.sessions.count) sessions · \(modeStore.semesterName)")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            // Mode picker — segmented control is reliable on macOS
            Picker("", selection: Binding(
                get: { modeStore.currentMode },
                set: { modeStore.currentMode = $0; modeStore.saveMode() }
            )) {
                Text("🎓 College").tag(StudyMode.college)
                Text("📚 Personal").tag(StudyMode.personal)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            todayBadge
            
            Button { showSubjectsSheet = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill").font(.system(size: 11))
                    Text("Subjects").font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1)).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            Button { exportSessions() } label: {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 14)).foregroundColor(.accentColor)
                    .padding(10).background(Color.accentColor.opacity(0.1)).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Export Study Sessions as CSV")
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
    }
    
    func exportSessions() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "studynotch_export.csv"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let csv = store.exportToCSV()
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    var todayBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Today").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            Text(fmtDur(store.todayTotal))
                .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.green.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Legacy tab bar replaced by 4-tab structure

    // ── HISTORY TAB ───────────────────────────────────────────────────────────

    var historyTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if store.sessions.isEmpty {
                    empty("clock.badge.questionmark", "No sessions yet.\nStart the timer to record your first session.")
                } else {
                    ForEach(store.byDay, id: \.day) { group in
                        Section {
                            ForEach(group.sessions) { s in sessionRow(s); Divider().padding(.leading, 56) }
                        } header: { dayHeader(group.day, sessions: group.sessions) }
                    }
                }
            }.padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if !store.sessions.isEmpty {
                Button(action: confirmClearAll) {
                    Label("Clear All Sessions", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain).padding(.vertical, 10)
                .frame(maxWidth: .infinity).background(.ultraThinMaterial)
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session)
        }
    }

    func dayHeader(_ day: String, sessions: [StudySession]) -> some View {
        HStack {
            Text(day).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            Spacer()
            Text(fmtDur(sessions.reduce(0){$0+$1.duration}))
                .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.accentColor)
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    func sessionRow(_ s: StudySession) -> some View {
        let tf = DateFormatter(); tf.timeStyle = .short
        let sc = subjectColor(s.subject)
        return HStack(spacing: 12) {

            // Subject avatar — coloured ring + initial
            ZStack {
                Circle()
                    .fill(sc.opacity(0.12))
                    .overlay(Circle().stroke(sc.opacity(0.3), lineWidth: 1))
                Text(String(s.subject.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(sc)
            }
            .frame(width: 38, height: 38)
            // Tap avatar to open subject dashboard
            .onTapGesture { SubjectDashboardWindowController.show(subject: s.subject) }
            .help("Open \(s.subject) dashboard")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(s.subject)
                        .font(.system(size: 13, weight: .semibold))
                    if s.isManual {
                        Text("Manual")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if s.difficulty > 0 {
                        HStack(spacing: 1) {
                            ForEach(1...s.difficulty, id: \.self) { i in
                                Image(systemName: i <= s.difficulty ? "star.fill" : "star")
                                    .font(.system(size: 7))
                                    .foregroundColor(i <= s.difficulty ? diffColor(s.difficulty) : .secondary.opacity(0.2))
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 9)).foregroundColor(.secondary)
                    Text("\(tf.string(from: s.startTime)) – \(tf.string(from: s.endTime))")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    if s.distractions.count > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.slash").font(.system(size: 8))
                            Text("\(s.distractions.count)")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.orange.opacity(0.8))
                    }
                }
                if !s.notes.isEmpty {
                    Text(s.notes)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer()

            // Duration chip
            Text(fmtDur(s.duration))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(sc)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(sc.opacity(0.1))
                .clipShape(Capsule())

            // Replay
            Button { SessionReplayWindowController.present(s) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(sc.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Replay session")

            // Edit
            Button { editingSession = s } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Edit notes & difficulty")

            // Delete
            Button { store.delete(s) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    func confirmClearAll() {
        let a = NSAlert()
        a.messageText = "Delete All Sessions?"
        a.informativeText = "This cannot be undone. Your subject list will be kept."
        a.addButton(withTitle: "Delete All"); a.addButton(withTitle: "Cancel")
        a.alertStyle = .critical
        if a.runModal() == .alertFirstButtonReturn { store.deleteAll() }
    }

    // ── COLLEGE MODE TAB ──────────────────────────────────────────────────────

    @State private var showAddSubject  = false
    @State private var showResetSheet  = false
    @State private var editingSession  : StudySession? = nil
    @State private var editingSubject  : CollegeSubject?

    var collegeModeTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Semester header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(modeStore.semesterName).font(.system(size: 16, weight: .bold))
                        if let end = modeStore.semesterEnd {
                            let days = Int(end.timeIntervalSinceNow / 86400)
                            Text(days > 0 ? "\(days) days until semester ends" : "Semester ended")
                                .font(.system(size: 11)).foregroundColor(days < 14 ? .orange : .secondary)
                        }
                    }
                    Spacer()
                    Button("Reset Semester") { showResetSheet = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .font(.system(size: 12))
                }

                Divider()

                // Subject cards
                if modeStore.collegeSubjects.isEmpty {
                    empty("tray", "No subjects added yet.\nTap + to add your courses for this semester.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(modeStore.collegeSubjects) { sub in
                            subjectCard(sub)
                        }
                    }
                }

                // Add button
                Button { showAddSubject = true } label: {
                    Label("Add Subject", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .sheet(isPresented: $showAddSubject) { AddSubjectSheet() }
        .sheet(isPresented: $showResetSheet) { ResetSemesterSheet() }
        .sheet(item: $editingSubject)        { sub in EditSubjectSheet(subject: sub) }
    }

    func subjectCard(_ sub: CollegeSubject) -> some View {
        let sessions  = store.sessions.filter { $0.subject == sub.name && $0.mode == StudyMode.college.rawValue }
        let totalMins = Int(sessions.reduce(0){$0+$1.duration} / 60)
        let color     = SubjectStore.shared.color(for: sub.name)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 3)
                Text(sub.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Spacer()
                // Dashboard button
                Button {
                    SubjectDashboardWindowController.show(subject: sub.name)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11)).foregroundColor(color.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Open \(sub.name) dashboard")

                Button { modeStore.deleteSubject(sub) } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            if let ct = sub.countdownText {
                HStack(spacing: 4) {
                    Image(systemName: "alarm").font(.system(size: 10)).foregroundColor(.orange)
                    Text(ct).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.orange)
                }
            } else if sub.examDate == nil {
                Text("No exam date set").font(.system(size: 10)).foregroundColor(.secondary)
            }
            HStack {
                Image(systemName: "clock").font(.system(size: 10)).foregroundColor(.secondary)
                Text("\(totalMins)min studied").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("Edit") { editingSubject = sub }
                    .font(.system(size: 10)).foregroundColor(.accentColor).buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(color.opacity(0.2), lineWidth: 1))
    }

    // ── PERSONAL COURSES TAB ──────────────────────────────────────────────────

    @State private var showAddCourse = false

    var personalModeTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                // AI distraction analysis banner
                if !modeStore.personalCourses.isEmpty {
                    aiDistractionBanner
                }

                if modeStore.personalCourses.isEmpty {
                    empty("books.vertical", "No personal courses yet.\nAdd the courses you're studying on your own.")
                } else {
                    ForEach(modeStore.personalCourses) { course in
                        courseCard(course)
                    }
                }

                Button { showAddCourse = true } label: {
                    Label("Add Course", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .sheet(isPresented: $showAddCourse) { AddCourseSheet() }
    }

    var aiDistractionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").foregroundColor(.purple)
                Text("Focus Analysis").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    ai.analyzePersonalCourses()
                } label: {
                    if ai.isLoadingCourseAnalysis {
                        ProgressView().scaleEffect(0.7).frame(width: 50)
                    } else {
                        Text("Analyse").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(ai.isLoadingCourseAnalysis)
            }
            if !ai.courseAnalysisResult.isEmpty {
                MarkdownText(ai.courseAnalysisResult)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Ask AI if your course list is focused or scattered — and what to finish vs skip.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.purple.opacity(0.15), lineWidth: 1))
    }

    func courseCard(_ course: PersonalCourse) -> some View {
        let sessions = store.sessions.filter { $0.subject == course.name && $0.mode == StudyMode.personal.rawValue }
        let totalMins = Int(sessions.reduce(0){$0+$1.duration} / 60)
        let statusColor: Color = course.status == .active ? .green : course.status == .completed ? .blue : course.status == .paused ? .orange : .red

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name).font(.system(size: 14, weight: .bold))
                    Text(course.field).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                // Status badge
                Text(course.status.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.12)).clipShape(Capsule())
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Progress").font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(course.progress)%").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(statusColor)
                            .frame(width: geo.size.width * CGFloat(course.progress) / 100, height: 6)
                    }
                }.frame(height: 6)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10)).foregroundColor(.secondary)
                    Text("\(totalMins)min").font(.system(size: 10)).foregroundColor(.secondary)
                }
                if !course.aiVerdict.isEmpty {
                    Text(course.aiVerdict).font(.system(size: 10)).foregroundColor(.purple)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer()
                // Status cycle button
                Menu {
                    ForEach(CourseStatus.allCases, id: \.self) { status in
                        Button(status.rawValue) {
                            var updated = course; updated.status = status
                            modeStore.updateCourse(updated)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { modeStore.deleteCourse(course) } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // ── CHARTS TAB ────────────────────────────────────────────────────────────

    @State private var chartsVisible = false
    // Charts interactivity
    @State private var selectedBarDay   : String? = nil
    @State private var selectedHour     : Int?    = nil
    @State private var selectedSubject  : String? = nil
    @State private var showDayDetail    = false
    @State private var showHourDetail   = false

    var chartsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                weeklyBarChart
                    .offset(y: chartsVisible ? 0 : 24)
                    .opacity(chartsVisible ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: chartsVisible)
                subjectDonutChart
                    .offset(y: chartsVisible ? 0 : 24)
                    .opacity(chartsVisible ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: chartsVisible)
                hourlyHeatmap
                    .offset(y: chartsVisible ? 0 : 24)
                    .opacity(chartsVisible ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25), value: chartsVisible)
                difficultyTrend
                    .offset(y: chartsVisible ? 0 : 24)
                    .opacity(chartsVisible ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: chartsVisible)
            }
            .padding(20)
        }
        .onAppear {
            chartsVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation { chartsVisible = true }
            }
        }
    }

    // ── Weekly bar chart ──────────────────────────────────────────────────────

    var weeklyBarChart: some View {
        let data = last7DaysData()
        return chartCard("Study Hours — Last 7 Days", icon: "calendar", color: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                Chart(data, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Hours", item.hours)
                    )
                    .foregroundStyle(
                        selectedBarDay == nil || selectedBarDay == item.day
                            ? LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top)
                            : LinearGradient(colors: [.blue.opacity(0.25), .cyan.opacity(0.25)], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if item.hours > 0 {
                            Text(String(format: "%.1f", item.hours))
                                .font(.system(size: 9))
                                .foregroundColor(selectedBarDay == item.day ? .blue : .secondary)
                                .fontWeight(selectedBarDay == item.day ? .bold : .regular)
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let day: String = proxy.value(atX: location.x) else { return }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedBarDay = selectedBarDay == day ? nil : day
                                }
                            }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))h").font(.system(size: 10)) } }
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { if let s = v.as(String.self) { Text(s).font(.system(size: 10)) } }
                    }
                }
                .frame(height: 160)

                // Session list for selected day
                if let day = selectedBarDay {
                    let daySessions = sessionsForBarDay(day)
                    if !daySessions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Sessions on \(day)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.blue)
                                Spacer()
                                Button { withAnimation { selectedBarDay = nil } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(daySessions.prefix(5)) { s in
                                HStack(spacing: 8) {
                                    Circle().fill(subjectColor(s.subject)).frame(width: 6, height: 6)
                                    Text(s.subject).font(.system(size: 11)).lineLimit(1)
                                    Spacer()
                                    Text(fmtDur(s.duration))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(s.startTime, format: .dateTime.hour().minute())
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.blue.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    // Returns sessions matching a short day label ("Mon" etc.) within the current week
    func sessionsForBarDay(_ day: String) -> [StudySession] {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return store.sessions.filter {
            fmt.string(from: $0.date) == day &&
            Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    func last7DaysData() -> [(day: String, hours: Double)] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        return (0..<7).reversed().map { offset -> (String, Double) in
            let date  = cal.date(byAdding: .day, value: -offset, to: Date())!
            let label = fmt.string(from: date)
            let secs  = store.sessions
                .filter { cal.isDate($0.date, inSameDayAs: date) }
                .reduce(0.0) { $0 + $1.duration }
            return (label, secs / 3600)
        }
    }

    // ── Subject donut chart ───────────────────────────────────────────────────

    var subjectDonutChart: some View {
        let totals = store.subjectTotals.prefix(6)
        let grand  = totals.reduce(0.0) { $0 + $1.total }
        guard grand > 0 else { return AnyView(EmptyView()) }

        return AnyView(chartCard("Time by Subject", icon: "chart.pie", color: .purple) {
            HStack(spacing: 20) {
                if #available(macOS 14.0, *) {
                    Chart(Array(totals), id: \.subject) { item in
                        SectorMark(
                            angle: .value("Time", item.total),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(subjectColor(item.subject))
                        .cornerRadius(4)
                    }
                    .frame(width: 140, height: 140)
                } else {
                    // Fallback bar chart for macOS 13
                    Chart(Array(totals), id: \.subject) { item in
                        BarMark(x: .value("Subject", item.subject),
                                y: .value("Time", item.total))
                        .foregroundStyle(subjectColor(item.subject))
                    }
                    .frame(width: 140, height: 140)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(totals), id: \.subject) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSubject = selectedSubject == item.subject ? nil : item.subject
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(subjectColor(item.subject))
                                    .frame(width: selectedSubject == item.subject ? 10 : 8,
                                           height: selectedSubject == item.subject ? 10 : 8)
                                    .shadow(color: subjectColor(item.subject).opacity(selectedSubject == item.subject ? 0.6 : 0), radius: 4)
                                Text(item.subject)
                                    .font(.system(size: 11, weight: selectedSubject == item.subject ? .bold : .regular))
                                    .lineLimit(1)
                                Spacer()
                                Text(fmtDur(item.total))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(selectedSubject == item.subject ? subjectColor(item.subject) : .secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(selectedSubject == item.subject
                                        ? subjectColor(item.subject).opacity(0.1)
                                        : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    if let sub = selectedSubject {
                        let subSessions = store.sessions.filter { $0.subject == sub }
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.system(size: 9))
                            Text("\(subSessions.count) sessions · avg \(fmtDur(subSessions.isEmpty ? 0 : subSessions.map(\.duration).reduce(0,+) / Double(subSessions.count)))")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        })
    }

    // ── Hourly heatmap ────────────────────────────────────────────────────────

    var hourlyHeatmap: some View {
        let data = hourlyData()
        let maxVal = data.map(\.count).max() ?? 1
        return chartCard("When Do You Study?", icon: "clock.fill", color: .orange) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { hour in
                        let count = data.first(where: { $0.hour == hour })?.count ?? 0
                        let intensity = maxVal > 0 ? Double(count) / Double(maxVal) : 0
                        let isSelected = selectedHour == hour
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected
                                      ? Color.orange.opacity(0.9)
                                      : Color.orange.opacity(0.1 + intensity * 0.9))
                                .frame(height: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isSelected ? Color.white.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                                .overlay(
                                    isSelected
                                        ? Text("\(count)").font(.system(size: 7, weight: .bold)).foregroundColor(.white)
                                        : nil
                                )
                            if hour % 6 == 0 {
                                Text("\(hour)h").font(.system(size: 8)).foregroundColor(.secondary)
                            } else {
                                Text("").font(.system(size: 8))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedHour = selectedHour == hour ? nil : hour
                            }
                        }
                        .help("\(hour):00 – \(count) session\(count == 1 ? "" : "s")")
                    }
                }
                HStack {
                    Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
                    LinearGradient(colors: [.orange.opacity(0.1), .orange], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 6).cornerRadius(3)
                    Text("More").font(.system(size: 9)).foregroundColor(.secondary)
                }

                // Sessions at selected hour
                if let h = selectedHour {
                    let cal = Calendar.current
                    let hourSessions = store.sessions.filter {
                        cal.component(.hour, from: $0.startTime) == h
                    }
                    if !hourSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(h):00 — \(hourSessions.count) session\(hourSessions.count == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                                Spacer()
                                Button { withAnimation { selectedHour = nil } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            ForEach(hourSessions.prefix(4)) { s in
                                HStack(spacing: 8) {
                                    Circle().fill(subjectColor(s.subject)).frame(width: 6, height: 6)
                                    Text(s.subject).font(.system(size: 11)).lineLimit(1)
                                    Spacer()
                                    Text(fmtDur(s.duration))
                                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                    Text(s.date, format: .dateTime.month(.abbreviated).day())
                                        .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    func hourlyData() -> [(hour: Int, count: Int)] {
        var counts = [Int: Int]()
        let cal = Calendar.current
        for s in store.sessions {
            let h = cal.component(.hour, from: s.startTime)
            counts[h, default: 0] += 1
        }
        return (0..<24).map { (hour: $0, count: counts[$0] ?? 0) }
    }

    // ── Difficulty trend ──────────────────────────────────────────────────────

    var difficultyTrend: some View {
        let data = last14DaysDifficulty()
        guard !data.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(chartCard("Difficulty Trend — Last 14 Days", icon: "star.fill", color: .yellow) {
            Chart(data, id: \.day) { item in
                LineMark(
                    x: .value("Day", item.day),
                    y: .value("Difficulty", item.avg)
                )
                .foregroundStyle(Color.yellow)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .symbol(.circle)
                .symbolSize(30)

                AreaMark(
                    x: .value("Day", item.day),
                    y: .value("Difficulty", item.avg)
                )
                .foregroundStyle(LinearGradient(colors: [.yellow.opacity(0.3), .clear],
                                                startPoint: .top, endPoint: .bottom))
            }
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5]) { v in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)★").font(.system(size: 9)) } }
                }
            }
            .frame(height: 120)
        })
    }

    func last14DaysDifficulty() -> [(day: String, avg: Double)] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "d/M"
        return (0..<14).reversed().compactMap { offset -> (String, Double)? in
            let date    = cal.date(byAdding: .day, value: -offset, to: Date())!
            let rated   = store.sessions.filter {
                cal.isDate($0.date, inSameDayAs: date) && $0.difficulty > 0
            }
            guard !rated.isEmpty else { return nil }
            let avg = Double(rated.map(\.difficulty).reduce(0,+)) / Double(rated.count)
            return (fmt.string(from: date), avg)
        }
    }

    // ── Chart card wrapper ────────────────────────────────────────────────────

    func chartCard<Content: View>(_ title: String, icon: String, color: Color,
                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content()
        }
        .padding(16)
        .background(
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                LinearGradient(
                    colors: [color.opacity(0.04), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(colors: [color.opacity(0.25), Color.secondary.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }

    // ── STATS TAB ─────────────────────────────────────────────────────────────

    var statsTab: some View {
        StatsTabView()
    }

    // legacy helpers still used elsewhere
    func statCard(_ t: String, _ v: String, _ i: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: i).foregroundColor(c); Spacer() }
            Text(v).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.system(size: 11)).foregroundColor(.secondary)
        }.padding(16).background(c.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var avgSession: String {
        guard !store.sessions.isEmpty else { return "—" }
        return fmtDur(store.sessions.reduce(0){$0+$1.duration} / Double(store.sessions.count))
    }
    var avgDiffText: String {
        let d = store.avgDifficulty; return d > 0 ? String(format: "%.1f / 5", d) : "—"
    }
    var streak: Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while store.sessions.contains(where:{cal.isDate($0.date,inSameDayAs:day)}) { n+=1; day=cal.date(byAdding:.day,value:-1,to:day)! }
        return n
    }

    // ── AI COACH TAB ─────────────────────────────────────────────────────────

    var aiCoachTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                apiKeySection

                // AI Acts — auto-adjust plan
                aiActsCard

                aiCard("Smart Schedule",    "AI study plan for next 3 days",         "calendar.badge.plus",         .blue,   ai.isLoadingSchedule,       ai.scheduleResult,       "Generate") { ai.generateSchedule() }
                aiCard("Weekly Report",     "Performance summary + goals",            "chart.line.uptrend.xyaxis",   .purple, ai.isLoadingReport,         ai.reportResult,         "Generate") { ai.generateWeeklyReport() }
                aiCard("Study Style",       "Detect your focus patterns & best time", "person.fill.questionmark",    .teal,   ai.isLoadingStyle,          ai.styleResult,          "Analyse")  { ai.detectStudyStyle() }

                Divider()

                // Notion
                settingsCard("Notion", icon: "doc.richtext.fill", color: Color(red:0.15,green:0.15,blue:0.15)) {
                    NotionSetupView()
                }

                // Google Calendar
                settingsCard("Google Calendar", icon: "calendar.badge.plus", color: Color(red:0.25,green:0.72,blue:1)) {
                    GoogleCalendarSetupView()
                }

                // Sound Settings
                settingsCard("Sound Alerts", icon: "speaker.wave.2.fill", color: .orange) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Milestone chimes, distraction sounds, break reminders")
                                .font(.system(size: 12))
                            Text("30-min chimes · Session start/end · Break at 90min · Exam warnings")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { SoundService.shared.enabled },
                            set: { SoundService.shared.enabled = $0 }
                        )).labelsHidden()
                    }
                }
            }.padding(24)
        }
    }

    var aiActsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill").font(.system(size: 16)).foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Actions").font(.system(size: 14, weight: .semibold))
                    Text("AI adjusts your weekly plan — not just suggests it").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }

            if !ai.planAdjustResult.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ai.planAdjustResult.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill").font(.system(size: 10)).foregroundColor(.green)
                            Text(line).font(.system(size: 11)).foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10).background(Color.green.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Apply These Changes to Weekly Plan") {
                    applyAIPlanAdjustments()
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .foregroundColor(.green)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.green.opacity(0.12)).clipShape(Capsule())
            }

            Button(ai.isAdjustingPlan ? "Analysing…" : "🤖 Auto-Adjust My Plan") {
                ai.autoAdjustPlan { _ in }
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 7)
            .background(ai.isAdjustingPlan ? Color.secondary.opacity(0.3) : Color.green)
            .clipShape(Capsule()).disabled(ai.isAdjustingPlan)

            Divider().overlay(Color.white.opacity(0.08))

            // ── Session Length Insight ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "timer").foregroundColor(.cyan)
                    Text("Optimal Session Length").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if ai.isAnalysingLength {
                        ProgressView().scaleEffect(0.6)
                    }
                }

                if !ai.sessionLengthInsight.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill").font(.system(size: 11)).foregroundColor(.cyan)
                        Text(ai.sessionLengthInsight)
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.cyan.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button(ai.isAnalysingLength ? "Analysing…" : "🕐 Analyse My Session Length") {
                    ai.analyseSessionLength()
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 6)
                .background(ai.isAnalysingLength ? Color.secondary.opacity(0.3) : Color.cyan)
                .clipShape(Capsule()).disabled(ai.isAnalysingLength)
            }
        }
        .padding(16).background(Color.green.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.15), lineWidth: 0.5))
    }

    func applyAIPlanAdjustments() {
        ai.autoAdjustPlan { adjustments in
            for (subject, newHours, _) in adjustments {
                SubjectStore.shared.setWeeklyGoal(subject: subject, hours: newHours)
            }
        }
    }

    var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "key.fill").font(.system(size: 11)).foregroundColor(.orange)
                Text("Groq API Key (100% Free)").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            }
            APIKeyField()
            Text("Free forever · No credit card · 14,400 requests/day")
                .font(.system(size: 10)).foregroundColor(.secondary)
            Button("Get Free Key at console.groq.com") {
                NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
            }
            .font(.system(size: 11))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
        }
        .padding(14).background(Color.orange.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func settingsCard<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            content()
        }
        .padding(16)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.15), lineWidth: 1))
    }

    func aiCard(_ title: String,_ subtitle: String,_ icon: String,_ color: Color,
                _ loading: Bool,_ result: String,_ btnLabel: String, action: @escaping ()->Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: action) {
                    if loading { ProgressView().scaleEffect(0.75).frame(width: 60) }
                    else { Text(btnLabel).font(.system(size: 12, weight: .medium)) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(loading)
            }
            if !result.isEmpty {
                Divider()
                MarkdownText(result)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16).background(color.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.15), lineWidth: 1))
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func empty(_ icon: String, _ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
            Text(msg).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, 40)
    }

    func fmtDur(_ d: TimeInterval) -> String {
        let h=Int(d)/3600; let m=(Int(d)%3600)/60
        return h>0 ? "\(h)h \(m)m" : m>0 ? "\(m)m" : "\(Int(d))s"
    }
    let palette:[Color] = [.blue,.green,.orange,.purple,.red,.cyan,.pink,.yellow]
    func subjectColor(_ s: String) -> Color { SubjectStore.shared.color(for: s) }
    func diffColor(_ d: Int)->Color { [.green,.yellow,.yellow,.orange,.red][max(0,d-1)] }
}

// ── Add Subject Sheet ─────────────────────────────────────────────────────────

struct AddSubjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var modeStore = ModeStore.shared
    @State private var name      = ""
    @State private var examDate  = Date().addingTimeInterval(60*86400)
    @State private var hasExam   = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Subject").font(.system(size: 16, weight: .bold)).padding(.top, 20)
            VStack(alignment: .leading, spacing: 12) {
                field("Subject Name", text: $name, placeholder: "e.g. Cybersecurity")
                Toggle("Has exam date", isOn: $hasExam)
                if hasExam {
                    DatePicker("Exam Date", selection: $examDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }
            }.padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Add") {
                    var sub = CollegeSubject(name: name)
                    if hasExam { sub.examDate = examDate }
                    modeStore.addSubject(sub); dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.bottom, 20)
        }.frame(width: 360)
    }

    func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

// ── Edit Subject Sheet ────────────────────────────────────────────────────────

struct EditSubjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var modeStore = ModeStore.shared
    var subject: CollegeSubject
    @State private var name     : String
    @State private var hasExam  : Bool
    @State private var examDate : Date

    init(subject: CollegeSubject) {
        self.subject  = subject
        _name     = State(initialValue: subject.name)
        _hasExam  = State(initialValue: subject.examDate != nil)
        _examDate = State(initialValue: subject.examDate ?? Date().addingTimeInterval(30*86400))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Subject").font(.system(size: 16, weight: .bold)).padding(.top, 20)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Name").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    TextField("Subject name", text: $name).textFieldStyle(.roundedBorder)
                }
                Toggle("Has exam date", isOn: $hasExam)
                if hasExam {
                    DatePicker("Exam Date", selection: $examDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                }
            }.padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Save") {
                    var updated = subject; updated.name = name
                    updated.examDate = hasExam ? examDate : nil
                    modeStore.updateSubject(updated); dismiss()
                }.buttonStyle(PrimaryButtonStyle())
            }.padding(.bottom, 20)
        }.frame(width: 360)
    }
}

// ── Reset Semester Sheet ──────────────────────────────────────────────────────

struct ResetSemesterSheet: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var modeStore = ModeStore.shared
    @State private var newName = ""
    @State private var newEnd  = Date().addingTimeInterval(120*86400)
    @State private var hasEnd  = true

    var body: some View {
        VStack(spacing: 20) {
            Text("New Semester").font(.system(size: 16, weight: .bold)).padding(.top, 20)
            Text("This will clear all current subjects.\nSession history is kept.")
                .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Semester Name").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    TextField("e.g. Fall 2026", text: $newName).textFieldStyle(.roundedBorder)
                }
                Toggle("Set end date", isOn: $hasEnd)
                if hasEnd {
                    DatePicker("Ends", selection: $newEnd, displayedComponents: .date).datePickerStyle(.compact)
                }
            }.padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Reset") {
                    modeStore.resetSemester(newName: newName.isEmpty ? "New Semester" : newName,
                                            newEnd: hasEnd ? newEnd : nil)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .foregroundColor(.white)
                .background(Color.red).clipShape(RoundedRectangle(cornerRadius: 9))
            }.padding(.bottom, 20)
        }.frame(width: 360)
    }
}

// ── Add Personal Course Sheet ─────────────────────────────────────────────────

struct AddCourseSheet: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var modeStore = ModeStore.shared
    @State private var name       = ""
    @State private var field      = ""
    @State private var motivation = ""
    @State private var hasTarget  = false
    @State private var targetDate = Date().addingTimeInterval(60*86400)

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Course").font(.system(size: 16, weight: .bold)).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetField("Course Name", text: $name,       placeholder: "e.g. SwiftUI Mastery")
                    sheetField("Field / Category", text: $field, placeholder: "e.g. iOS Dev, AI, Design")
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Why are you taking this?").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        TextEditor(text: $motivation)
                            .font(.system(size: 12)).frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2)))
                    }
                    Toggle("Set target finish date", isOn: $hasTarget)
                    if hasTarget {
                        DatePicker("Target", selection: $targetDate, displayedComponents: .date).datePickerStyle(.compact)
                    }
                }.padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Add") {
                    var c = PersonalCourse(name: name, field: field, motivation: motivation)
                    if hasTarget { c.targetDate = targetDate }
                    modeStore.addCourse(c); dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.bottom, 20)
        }.frame(width: 380, height: 420)
    }

    func sheetField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

// ── API Key Field ─────────────────────────────────────────────────────────────

struct APIKeyField: View {
    @State private var key      = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
    @State private var revealed = false
    var body: some View {
        HStack {
            if revealed { TextField("gsk_...", text: $key).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)) }
            else        { SecureField("gsk_...", text: $key).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)) }
            Button { revealed.toggle() } label: {
                Image(systemName: revealed ? "eye.slash" : "eye").font(.system(size: 12)).foregroundColor(.secondary)
            }.buttonStyle(.plain)
            Button("Save") { UserDefaults.standard.set(key, forKey: "groq_api_key") }
                .buttonStyle(PrimaryButtonStyle()).font(.system(size: 11)).disabled(key.isEmpty)
        }
        .padding(8).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────

// ── Quick Notes Tab ───────────────────────────────────────────────────────────

struct QuickNotesTab: View {
    @Bindable var store = SessionStore.shared
    @Bindable var subStore = SubjectStore.shared
    var groupedNotes: [(subject: String, notes: [QuickNote])] {
        var map: [String: [QuickNote]] = [:]
        for n in store.quickNotes { map[n.subject, default: []].append(n) }
        return map.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Quick Notes")
                    .font(.system(size: 15, weight: .bold))
                Text("\(store.quickNotes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1)).clipShape(Capsule())
                Spacer()
                Text("Saved from the notch during sessions")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)

            Divider()

            if store.quickNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 36)).foregroundColor(.secondary.opacity(0.3))
                    Text("No quick notes yet")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                    Text("While a session is running, type a note in the notch\nand press Save or Send.")
                        .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedNotes, id: \.subject) { group in
                            Section {
                                ForEach(group.notes) { note in
                                    NoteRow(note: note)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(subStore.color(for: group.subject))
                                        .frame(width: 8, height: 8)
                                    Text(group.subject)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("\(group.notes.count)")
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 24).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

struct NoteRow: View {
    @Bindable var store = SessionStore.shared
    let note: QuickNote

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(fmt.string(from: note.date))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    if note.sentToTelegram {
                        HStack(spacing: 3) {
                            Image(systemName: "paperplane.fill").font(.system(size: 8))
                            Text("Sent to Telegram").font(.system(size: 9))
                        }
                        .foregroundColor(Color(red: 0.25, green: 0.72, blue: 1.0))
                    }
                }
            }
            Spacer()
            Button {
                store.deleteQuickNote(note)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 4)
    }
}

class AnalyticsWindowController: NSWindowController {
    static var shared: AnalyticsWindowController?
    static func show() {
        if let s = shared { 
            s.window?.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return 
        }
        let c = AnalyticsWindowController()
        shared = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    init() {
        let win = NSWindow(contentRect: NSRect(x:0,y:0,width:680,height:720),
                           styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Study Analytics"; win.titlebarAppearsTransparent = true
        win.center(); win.contentView = NSHostingView(rootView: AnalyticsView())
        win.minSize = NSSize(width: 500, height: 520)
        super.init(window: win); win.delegate = self
    }
    required init?(coder: NSCoder) { nil }
}
extension AnalyticsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        AnalyticsWindowController.shared = nil
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { NotchWindowController.shared?.window?.orderFrontRegardless() }
    }
}
