import SwiftUI
import AppKit

// ── Shared static formatters ──────────────────────────────────────────────────

private let shortTimeFmt: DateFormatter = {
    let f = DateFormatter(); f.timeStyle = .short; return f
}()

// ── Session End Dialog ────────────────────────────────────────────────────────
//
//  Used for BOTH finishing a live session AND logging a manual session.
//  When `isManualEntry` is true, the user supplies all time fields themselves.
//  When false (live timer finished), times are pre-filled but still editable —
//  any edit causes the session to be saved with `isManual = true`.

struct SessionEndView: View {
    // nil means manual entry (no live session data)
    let sessionData: (start: Date, end: Date, duration: TimeInterval,
                      distractions: [DistractionEvent], pauses: [PauseInterval],
                      appUsage: [String: TimeInterval])?

    /// Subject captured from the notch pill before the timer was reset
    var preselectedSubject: String = ""

    var isManualEntry: Bool { sessionData == nil }

    // ── Local state ───────────────────────────────────────────────────────────
    @State private var currentMode      : StudyMode       = ModeStore.shared.currentMode
    @State private var collegeSubjects  : [CollegeSubject] = ModeStore.shared.collegeSubjects
    @State private var subject          = ""
    @State private var selectedSubjectID: UUID?            = ModeStore.shared.activeSubjectID
    @State private var notes            = ""
    @State private var difficulty       = 0
    @State private var saved            = false
    @State private var cachedSuggestions: [String]         = []
    @State private var suggestedTasks   : [StudyTask]      = []   // tasks for auto-fill
    @State private var selectedTaskIDs  : Set<UUID>        = []   // user-checked tasks

    // ── Editable time state ───────────────────────────────────────────────────
    @State private var editStart        : Date = Date()   // fixed anchor for live sessions; derived from duration for manual entries
    @State private var editEnd          : Date = Date()   // real wall-clock finish time
    @State private var durationHours    : Int  = 1
    @State private var durationMinutes  : Int  = 0
    @State private var durationWasEdited: Bool = false

    var editedDuration : TimeInterval { TimeInterval(durationHours * 3600 + durationMinutes * 60) }
    var durationText   : String       { fmtDur(editedDuration) }

    /// For manual entries OR when duration was edited, derive start from end − duration
    /// so the start time is always logically consistent with the chosen duration.
    /// For unedited live sessions it stays as the real captured start.
    var effectiveStart: Date {
        (isManualEntry || durationWasEdited) ? editEnd.addingTimeInterval(-editedDuration) : editStart
    }

    @FocusState private var subjectFocused: Bool
    @FocusState private var notesFocused  : Bool

    var isCollege: Bool { currentMode == .college }

    var resolvedSubject: String {
        if isCollege {
            return collegeSubjects.first { $0.id == selectedSubjectID }?.name ?? ""
        }
        return subject
    }

    // True if this save will be marked manual
    var willBeManual: Bool { isManualEntry || durationWasEdited }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────────────
                VStack(spacing: 0) {
                    // Subject colour gradient bar — thicker + glowing
                    let subjectAccent = resolvedSubject.isEmpty
                        ? Color.accentColor
                        : SubjectStore.shared.color(for: resolvedSubject)

                    ZStack {
                        // Soft bloom below the bar
                        Rectangle()
                            .fill(subjectAccent.opacity(0.25))
                            .blur(radius: 8)
                            .frame(height: 8)
                            .offset(y: 3)

                        Rectangle()
                            .fill(LinearGradient(
                                colors: [subjectAccent.opacity(0.9), subjectAccent.opacity(0.3), .clear],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(height: 3)
                    }
                    .frame(height: 8)
                    .animation(.easeOut(duration: 0.3), value: resolvedSubject)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            if !resolvedSubject.isEmpty {
                                Circle()
                                    .fill(subjectAccent)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: subjectAccent, radius: 6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(isManualEntry ? "Log Study Session 📝" : "Session Complete 🎓")
                                .font(.system(size: 18, weight: .bold))
                            if willBeManual { manualBadge }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: resolvedSubject)

                        // Mode toggle
                        Picker("", selection: $currentMode) {
                            Text("🎓 College").tag(StudyMode.college)
                            Text("📚 Personal").tag(StudyMode.personal)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                        .onChange(of: currentMode) { newMode in
                            ModeStore.shared.currentMode = newMode
                            ModeStore.shared.saveMode()
                            selectedSubjectID = nil
                            subject = ""
                            refreshSuggestedTasks()
                        }

                        // ── Editable time pills ───────────────────────────────
                        timeEditRow
                    }
                    .padding(.top, 16).padding(.bottom, 16).padding(.horizontal, 24)
                }

                Divider()

                // ── Scrollable content ────────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        if isCollege { collegeSubjectPicker }
                        else         { personalSubjectField  }

                        difficultySection
                        if !suggestedTasks.isEmpty { taskChecklistSection }
                        notesSection

                        // Exam countdown (college only)
                        if isCollege,
                           let sub = collegeSubjects.first(where: { $0.id == selectedSubjectID }),
                           let ct  = sub.countdownText {
                            examBanner(sub.name, ct)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 16)
                }
                
                // ── App Usage Summary ─────────────────────────────────────────
                if let apps = sessionData?.appUsage, !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "apps.iphone").foregroundColor(.secondary)
                            Text("Top Apps Used").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                        }
                        
                        let sortedApps = apps.sorted { $0.value > $1.value }.prefix(3)
                        HStack(spacing: 8) {
                            ForEach(Array(sortedApps), id: \.key) { bid, duration in
                                let name = appName(bid)
                                appChip(name, duration)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                }

                Divider()

                // ── Buttons ───────────────────────────────────────────────────
                HStack(spacing: 12) {
                    Button("Skip") { closeWindow() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(action: saveSession) {
                        Label(isManualEntry ? "Log Session" : "Save Session",
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(resolvedSubject.trimmingCharacters(in: .whitespaces).isEmpty
                              || editedDuration <= 0)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(20)
            }

            // Saved flash
            if saved {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundColor(.green)
                        Text(isManualEntry ? "Logged!" : "Saved!")
                            .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    }
                }.transition(.opacity)
            }
        }
        .frame(width: 440, height: isManualEntry ? 580 : 560)
        .onAppear {
            currentMode     = ModeStore.shared.currentMode
            collegeSubjects = ModeStore.shared.collegeSubjects
            if let id = ModeStore.shared.activeSubjectID { selectedSubjectID = id }
            cachedSuggestions = SessionStore.shared.rankedSuggestions()
            subjectFocused    = !isCollege

            // Seed time & duration fields
            if let sd = sessionData {
                editStart = sd.start
                editEnd   = sd.end   // real wall-clock finish time (includes pauses)
                // Use actual seconds — don't round, preserve real duration
                // Ensure at least 1 minute so save button is never disabled
                let secs = max(60, Int(sd.duration))
                durationHours   = secs / 3600
                durationMinutes = (secs % 3600) / 60
            } else {
                // Manual entry: default 1h 00m ending now
                editStart       = Date().addingTimeInterval(-3600)
                editEnd         = Date()
                durationHours   = 1
                durationMinutes = 0
            }
            // Sync subject from notch pill using the pre-captured value
            // (StudyTimer.currentSubject is already "" by this point because reset() cleared it)
            let notchSubject = preselectedSubject.isEmpty
                ? StudyTimer.shared.currentSubject   // fallback for manual entry
                : preselectedSubject

            if !notchSubject.isEmpty {
                if !isCollege {
                    // Always override with notch pill subject
                    subject = notchSubject
                    cachedSuggestions = SessionStore.shared.rankedSuggestions()
                } else {
                    // Always override with notch pill subject match (remove guard)
                    if let match = ModeStore.shared.collegeSubjects.first(where: {
                        $0.name.lowercased() == notchSubject.lowercased() ||
                        notchSubject.lowercased().contains($0.name.lowercased())
                    }) {
                        selectedSubjectID = match.id
                    }
                }
            }
            // Load tasks for auto-fill after subject is resolved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                refreshSuggestedTasks()
                autoFillNotesFromTasks()
                // Pre-fill notes from quick notes taken during session
                if notes.isEmpty && !StudyTimer.shared.sessionNotes.isEmpty {
                    notes = StudyTimer.shared.sessionNotes
                }
            }
        }
    }

    // ── Manual badge ──────────────────────────────────────────────────────────

    var manualBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "pencil").font(.system(size: 8, weight: .bold))
            Text("Manual").font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.5))
    }

    // ── Editable time row ─────────────────────────────────────────────────────
    //
    //  Three tappable pills: [Start]  →  [End]  |  [Duration]
    //  Clicking Start or End opens a compact DatePicker popover.
    //  Duration is derived and shown read-only (updates live).
    //  Duration is directly editable via steppers + text field.
    //  Start time is shown read-only. End = start + duration.

    var timeEditRow: some View {
        VStack(spacing: 8) {
            // ── Row 1: start pill (read-only) + distractions ──────────────────
            HStack(spacing: 8) {
                // For manual entries, start is derived live from end − duration
                statPill("play.fill",  shortTimeFmt.string(from: effectiveStart), .blue)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.4))
                statPill("stop.fill",  shortTimeFmt.string(from: editEnd),   .orange)
                Spacer()
                if let sd = sessionData, !sd.distractions.isEmpty {
                    statPill("bolt.slash.fill", "\(sd.distractions.count) dist.", .red)
                }
            }

            // ── Row 2: duration editor ────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(durationWasEdited ? .orange : .green)

                Text("Duration")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Hours stepper
                HStack(spacing: 4) {
                    Button { if durationHours > 0 { durationHours -= 1; durationWasEdited = true } } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)

                    Text("\(durationHours)h")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .frame(minWidth: 32, alignment: .center)

                    Button { durationHours += 1; durationWasEdited = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }

                Text(":")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary)

                // Minutes stepper (steps of 5)
                HStack(spacing: 4) {
                    Button {
                        durationMinutes = durationMinutes >= 5 ? durationMinutes - 5 : 55
                        if durationMinutes == 55 && durationHours > 0 { durationHours -= 1 }
                        durationWasEdited = true
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)

                    Text(String(format: "%02dm", durationMinutes))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .frame(minWidth: 38, alignment: .center)

                    Button {
                        durationMinutes = (durationMinutes + 5) % 60
                        if durationMinutes == 0 { durationHours += 1 }
                        durationWasEdited = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }

                // Edited indicator
                if durationWasEdited {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .transition(.scale)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(durationWasEdited
                        ? Color.orange.opacity(0.08)
                        : Color.green.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(durationWasEdited
                                ? Color.orange.opacity(0.25)
                                : Color.green.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }

    // ── College subject grid ──────────────────────────────────────────────────

    var collegeSubjectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Which subject?", icon: "graduationcap.fill")
            if collegeSubjects.isEmpty {
                Text("No subjects yet — add them in Analytics → College Mode")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .padding(10).frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(collegeSubjects) { sub in subjectButton(sub) }
                }
            }
        }
    }

    func subjectButton(_ sub: CollegeSubject) -> some View {
        let selected  = selectedSubjectID == sub.id
        let subColor  = SubjectStore.shared.color(for: sub.name)
        return Button {
            selectedSubjectID = sub.id
            refreshSuggestedTasks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { autoFillNotesFromTasks() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(selected ? subColor : Color.secondary.opacity(0.2))
                    .frame(width: 7, height: 7)
                    .shadow(color: selected ? subColor.opacity(0.5) : .clear, radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sub.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(selected ? .accentColor : .primary)
                        .lineLimit(1)
                    if let ct = sub.countdownText {
                        Text(ct).font(.system(size: 9)).foregroundColor(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? subColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? subColor.opacity(0.5) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // ── Personal subject field ────────────────────────────────────────────────

    var personalSubjectField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("What were you studying?", icon: "book.fill")
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary).font(.system(size: 13))
                TextField("Subject or course…", text: $subject)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($subjectFocused)
                    .onChange(of: subject) { _ in
                        cachedSuggestions = SessionStore.shared.rankedSuggestions(filter: subject)
                        refreshSuggestedTasks()
                    }
                if !subject.isEmpty {
                    Button { subject = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(subjectFocused ? 0.5 : 0.15),
                                      lineWidth: 1.5))

            if !cachedSuggestions.isEmpty {
                Text(subject.isEmpty ? "Recent subjects" : "Suggestions")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                FlowLayout(spacing: 7) {
                    ForEach(cachedSuggestions.prefix(8), id: \.self) { s in
                        Button { subject = s; subjectFocused = false } label: {
                            Text(s).font(.system(size: 12, weight: .medium))
                                .foregroundColor(subject == s ? .white : .accentColor)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(subject == s ? Color.accentColor
                                                         : Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // ── Difficulty ────────────────────────────────────────────────────────────

    var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("How hard was it?", icon: "brain.head.profile")
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { i in
                    Button { difficulty = i } label: {
                        VStack(spacing: 3) {
                            Image(systemName: i <= difficulty ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundColor(i <= difficulty ? starColor(difficulty)
                                                                 : .secondary.opacity(0.35))
                            if      i == 1 { Text("Hard").font(.system(size: 8)).foregroundColor(.secondary) }
                            else if i == 3 { Text("OK")  .font(.system(size: 8)).foregroundColor(.secondary) }
                            else if i == 5 { Text("Easy").font(.system(size: 8)).foregroundColor(.secondary) }
                            else           { Text(" ")   .font(.system(size: 8)) }
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 4)
        }
    }

    // ── Task checklist — auto-filled from pending tasks for this subject ─────

    var taskChecklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checklist").font(.system(size: 11)).foregroundColor(.accentColor)
                Text("Tasks worked on?").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Text("Tap to mark complete").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.6))
            }

            VStack(spacing: 5) {
                ForEach(suggestedTasks) { task in
                    let checked = selectedTaskIDs.contains(task.id)
                    Button {
                        if checked { selectedTaskIDs.remove(task.id) }
                        else       { selectedTaskIDs.insert(task.id) }
                        // Auto-append task title to notes
                        appendTaskToNotes(task, checked: !checked)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundColor(checked ? .green : .secondary.opacity(0.5))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 12, weight: checked ? .medium : .regular))
                                    .foregroundColor(checked ? .primary : .primary.opacity(0.75))
                                    .strikethrough(checked)
                                    .lineLimit(2)
                                // Type + progress badge
                                if task.taskType != .general {
                                    HStack(spacing: 4) {
                                        Image(systemName: task.taskType.icon)
                                            .font(.system(size: 8))
                                        if task.taskTotal > 0 {
                                            Text("\(task.taskDone)/\(task.taskTotal) \(task.taskType.unit)")
                                                .font(.system(size: 9, design: .monospaced))
                                        } else {
                                            Text(task.taskType.rawValue)
                                                .font(.system(size: 9))
                                        }
                                    }
                                    .foregroundColor(.secondary.opacity(0.7))
                                }
                            }

                            Spacer()

                            if task.isOverdue {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10)).foregroundColor(.red.opacity(0.7))
                            } else if task.dueSoon {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10)).foregroundColor(.orange.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(checked
                            ? Color.green.opacity(0.08)
                            : Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(checked ? Color.green.opacity(0.25) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func refreshSuggestedTasks() {
        let sub = resolvedSubject.trimmingCharacters(in: .whitespaces)
        guard !sub.isEmpty else { suggestedTasks = []; return }
        // Pending tasks for this subject (or subject-less tasks)
        suggestedTasks = TaskStore.shared.tasks.filter {
            !$0.isCompleted &&
            ($0.subject.lowercased() == sub.lowercased() || $0.subject.isEmpty)
        }.sorted { lhs, rhs in
            // Overdue first, then due soon, then by creation
            if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
            if lhs.dueSoon  != rhs.dueSoon   { return lhs.dueSoon   }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func appendTaskToNotes(_ task: StudyTask, checked: Bool) {
        if checked {
            // Build a rich task note line with type context
            var line = "• \(task.title)"
            if task.taskType != .general {
                if task.taskType.hasProgress && task.taskTotal > 0 {
                    line += " [\(task.taskType.rawValue): \(task.taskDone)/\(task.taskTotal) \(task.taskType.unit)]"
                } else {
                    line += " [\(task.taskType.rawValue)]"
                }
            }
            if !notes.contains(line) {
                notes += (notes.isEmpty ? "" : "\n") + line
            }
        } else {
            // Remove the line (match loosely by task title)
            notes = notes.components(separatedBy: "\n")
                .filter { !$0.contains("• \(task.title)") }
                .joined(separator: "\n")
        }
    }

    /// Auto-populate notes with a smart summary when the subject is first resolved
    func autoFillNotesFromTasks() {
        guard notes.isEmpty, !suggestedTasks.isEmpty else { return }
        let overdueLines = suggestedTasks.filter { $0.isOverdue }.map { "⚠️ \($0.title)" }
        let dueSoonLines = suggestedTasks.filter { $0.dueSoon && !$0.isOverdue }.map { "⏰ \($0.title)" }
        let hint = (overdueLines + dueSoonLines).prefix(2)
        if !hint.isEmpty {
            notes = hint.joined(separator: "\n")
        }
    }

    // ── Notes ─────────────────────────────────────────────────────────────────

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("What exactly did you cover?", icon: "note.text")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(notesFocused ? 0.5 : 0.15), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(nsColor: .textBackgroundColor)))
                if notes.isEmpty {
                    Text("e.g. Chapter 3 — OSI model, TCP vs UDP…")
                        .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.55))
                        .padding(10).allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden).background(.clear)
                    .focused($notesFocused).padding(6)
            }.frame(height: 90)
        }
    }

    // ── Exam countdown banner ─────────────────────────────────────────────────

    func examBanner(_ name: String, _ countdown: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) Exam").font(.system(size: 12, weight: .semibold))
                Text("Time remaining").font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Text(countdown)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
        }
        .padding(12).background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func label(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(.accentColor)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
        }
    }

    func starColor(_ d: Int) -> Color {
        // 1=Hard(red) → 5=Easy(green)
        [.red, .orange, .yellow, Color(red:0.6,green:0.9,blue:0.2), .green][max(0, d-1)]
    }

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60; let s = Int(d)%60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m \(s)s" : "\(Int(d))s"
    }

    func statPill(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color).padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12)).clipShape(Capsule())
    }

    func saveSession() {
        let trimmed = resolvedSubject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, editedDuration > 0 else { return }

        // For manual entries, derive start from end − duration so the start
        // time is always logically consistent with the chosen duration.
        let resolvedStart = effectiveStart
        let session = StudySession(
            subject      : trimmed,
            notes        : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            difficulty   : difficulty,
            mode         : currentMode.rawValue,
            date         : Calendar.current.startOfDay(for: resolvedStart),
            startTime    : resolvedStart,
            endTime      : editEnd,
            duration     : editedDuration,
            distractions : sessionData?.distractions ?? [],
            pauses       : sessionData?.pauses ?? [],
            isManual     : willBeManual,
            appUsage     : sessionData?.appUsage ?? [:]
        )

        SessionStore.shared.save(session)
        StudyTimer.shared.currentSubject = trimmed
        if isCollege { ModeStore.shared.activeSubjectID = nil }

        // Complete any tasks the user checked during this session
        for task in suggestedTasks where selectedTaskIDs.contains(task.id) {
            TaskStore.shared.complete(task)
        }

        // Push to Notion sessions database
        NotionService.shared.pushSession(session) { _ in }

        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { closeWindow() }
    }



    func appName(_ bid: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let name = path.lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return name
        }
        return bid.components(separatedBy: ".").last ?? bid
    }

    func appChip(_ name: String, _ duration: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 10, weight: .semibold))
            Text(fmtDur(duration)).font(.system(size: 9)).opacity(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }

    func closeWindow() {
        let ctrl = SessionEndWindowController.shared
        SessionEndWindowController.shared = nil
        ctrl?.window?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotchWindowController.shared?.window?.orderFrontRegardless()
        }
    }
}

// ── FlowLayout ────────────────────────────────────────────────────────────────

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}

// ── Visual Effect ─────────────────────────────────────────────────────────────

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blendingMode; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// ── Button Styles ─────────────────────────────────────────────────────────────

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundColor(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────

class SessionEndWindowController: NSWindowController {
    static var shared: SessionEndWindowController?

    // Called when a live timer finishes
    static func present(sessionData: (start: Date, end: Date, duration: TimeInterval,
                                       distractions: [DistractionEvent],
                                       pauses: [PauseInterval],
                                       appUsage: [String: TimeInterval]),
                        preselectedSubject: String = "") {
        if let existing = shared { existing.window?.close(); shared = nil }
        show(sessionData: sessionData, preselectedSubject: preselectedSubject)
    }

    // Called for manual log entry (no live session data)
    static func presentManual() {
        if let existing = shared { existing.window?.close(); shared = nil }
        show(sessionData: nil, preselectedSubject: StudyTimer.shared.currentSubject)
    }

    private static func show(sessionData: (start: Date, end: Date, duration: TimeInterval,
                                            distractions: [DistractionEvent],
                                            pauses: [PauseInterval],
                                            appUsage: [String: TimeInterval])?,
                              preselectedSubject: String = "") {
        let c = SessionEndWindowController(sessionData: sessionData,
                                           preselectedSubject: preselectedSubject)
        shared = c
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        c.window?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 2)
    }

    init(sessionData: (start: Date, end: Date, duration: TimeInterval,
                       distractions: [DistractionEvent], pauses: [PauseInterval],
                       appUsage: [String: TimeInterval])?,
         preselectedSubject: String = "") {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: sessionData == nil ? 580 : 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.minSize = NSSize(width: 380, height: 480)
        win.title = sessionData == nil ? "Log Study Session" : "Save Study Session"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(
            rootView: SessionEndView(sessionData: sessionData,
                                     preselectedSubject: preselectedSubject)
        )
        super.init(window: win)
        win.delegate = self
    }
    required init?(coder: NSCoder) { nil }
}

extension SessionEndWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SessionEndWindowController.shared = nil
        NSApp.setActivationPolicy(.accessory)
        // Restore notch panel focus without stealing full app activation
        NotchWindowController.shared?.window?.orderFrontRegardless()
    }
}
