import SwiftUI
import AppKit

// ── AI Plan Editor ────────────────────────────────────────────────────────────
//
//  Generates an AI study plan the user can EDIT before applying.
//  The AI sees ALL subjects (studied + not yet studied), tasks, exams.
//  User picks time range, adjusts hours per subject, then taps Apply.
//
// ─────────────────────────────────────────────────────────────────────────────

// ── Plan Entry (one row in the editable table) ────────────────────────────────

struct PlanEntry: Identifiable, Equatable {
    var id          = UUID()
    var subject     : String
    var hours       : Double      // planned hours for the range
    var days        : [Int]       // 0=Sun…6=Sat to study this
    var priority    : String      // "High" "Medium" "Low"
    var note        : String      // AI reasoning or user note
    var color       : Color

    var hoursText   : String { String(format: "%.1f h", hours) }
}

// ── Time range ────────────────────────────────────────────────────────────────

enum PlanRange: String, CaseIterable, Identifiable {
    case today   = "Today"
    case days3   = "3 Days"
    case week    = "1 Week"
    case custom  = "Custom"
    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .today:  return 1
        case .days3:  return 3
        case .week:   return 7
        case .custom: return 0   // user-set
        }
    }
}

// ── Window controller ─────────────────────────────────────────────────────────

class AIPlanEditorWindowController: NSWindowController {
    static var shared: AIPlanEditorWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "AI Plan Editor"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.minSize = NSSize(width: 520, height: 520)
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: AIPlanEditorView())
        let c = AIPlanEditorWindowController(window: win)
        shared = c
        c.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in AIPlanEditorWindowController.shared = nil }
    }
}

// ── Main view ─────────────────────────────────────────────────────────────────

struct AIPlanEditorView: View {
    var ai       = AIService.shared
    @Bindable var subStore = SubjectStore.shared
    @Bindable var sessions = SessionStore.shared
    @Bindable var taskStore = TaskStore.shared
    private let accent = Color(red: 0.2, green: 1.0, blue: 0.55)

    // ── State ──────────────────────────────────────────────────────────────────
    @State private var range        : PlanRange = .week
    @State private var customDays   : Int       = 5
    @State private var planEntries  : [PlanEntry] = []
    @State private var isGenerating : Bool      = false
    @State private var rawAIText    : String    = ""
    @State private var applied      : Bool      = false
    @State private var applyMessage : String    = ""
    @State private var showSuggestions: Bool    = true

    // Subjects AI suggests adding (not yet in any entry)
    @State private var suggestedNewSubjects: [String] = []
    @State private var selectedSubjects    : Set<String> = []  // user picks which to include
    @State private var showSubjectPicker   : Bool = true       // shown before generating

    var effectiveDays: Int { range == .custom ? customDays : range.dayCount }

    // All known subjects — case-insensitive deduplication
    var allSubjects: [String] {
        var seen  = Set<String>()   // lowercased for dedup
        var all   : [String] = []
        let raw   = sessions.knownSubjects + subStore.metas.map(\.name)
        for s in raw {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted { all.append(trimmed) }
        }
        return all.sorted()
    }

    // ── Body ──────────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.07))

            if planEntries.isEmpty && !isGenerating {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if isGenerating { generatingView }
                        if !suggestedNewSubjects.isEmpty && showSuggestions { suggestionsBar }
                        if !planEntries.isEmpty { planTable }
                        if !rawAIText.isEmpty { rawTextSection }
                    }
                    .padding(.bottom, 20)
                }
            }

            if !planEntries.isEmpty {
                Divider().overlay(Color.white.opacity(0.07))
                actionBar
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // ── Header ────────────────────────────────────────────────────────────────

    var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 32, height: 32)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14)).foregroundColor(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Plan Editor").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text("AI suggests — you decide. Edit before applying.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }

            // Time range picker
            HStack(spacing: 8) {
                Text("Plan for:").font(.system(size: 12)).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(PlanRange.allCases) { r in
                        Button { range = r } label: {
                            Text(r.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(range == r ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(range == r ? accent : Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if range == .custom {
                    Stepper("\(customDays) days", value: $customDays, in: 1...30)
                        .labelsHidden()
                    Text("\(customDays) days").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    if planEntries.isEmpty {
                        generate()
                    } else {
                        // Go back to picker for regeneration
                        withAnimation { planEntries = []; rawAIText = "" }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: planEntries.isEmpty ? "sparkles" : "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        Text(planEntries.isEmpty ? "Generate Plan" : "Change Subjects")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
        }
        .padding(16)
    }

    // ── Subject picker (pre-generation) ──────────────────────────────────────

    var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36)).foregroundColor(accent.opacity(0.7))
                    Text("Choose subjects for your plan")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text("Select which subjects the AI should plan for.\nDeselect any you don't need right now.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                if allSubjects.isEmpty {
                    Text("No subjects found. Log a study session or add subjects in Analytics first.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                } else {
                    // Select All / None controls
                    HStack {
                        Button("Select All") {
                            selectedSubjects = Set(allSubjects)
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(accent)

                        Text("·").foregroundColor(.secondary)

                        Button("Deselect All") {
                            selectedSubjects = []
                        }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.secondary)

                        Spacer()
                        Text("\(selectedSubjects.count) of \(allSubjects.count) selected")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)

                    // Subject grid with checkboxes
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(allSubjects, id: \.self) { s in
                            SubjectPickerCell(
                                subject: s,
                                color: subStore.color(for: s),
                                isSelected: selectedSubjects.contains(s),
                                sessions: sessions.sessions
                                    .filter { $0.subject == s }
                                    .reduce(0.0) { $0 + $1.duration }
                            ) {
                                if selectedSubjects.contains(s) {
                                    selectedSubjects.remove(s)
                                } else {
                                    selectedSubjects.insert(s)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Generate button (only active when subjects selected)
                Button {
                    generate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 13))
                        Text("Generate Plan for \(selectedSubjects.count) Subject\(selectedSubjects.count == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(selectedSubjects.isEmpty ? .white.opacity(0.3) : .black)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(selectedSubjects.isEmpty ? Color.white.opacity(0.08) : accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(selectedSubjects.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // ── Generating spinner ────────────────────────────────────────────────────

    var generatingView: some View {
        HStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text("Thinking about your subjects, tasks, and exams…")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding(16)
    }

    // ── Suggested new subjects bar ────────────────────────────────────────────

    var suggestionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.system(size: 12))
                Text("AI suggests adding these subjects to your plan:")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button { withAnimation { showSuggestions = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestedNewSubjects, id: \.self) { s in
                        Button {
                            addSubjectToPlan(s)
                            suggestedNewSubjects.removeAll { $0 == s }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 10))
                                Text(s).font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.07))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.2)), alignment: .top)
    }

    // ── Plan table ────────────────────────────────────────────────────────────

    var planTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Subject").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
                Text("Hours").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
                Text("Priority").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
                Text("").frame(width: 60)
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .background(Color.white.opacity(0.03))

            Divider().overlay(Color.white.opacity(0.06))

            ForEach($planEntries) { $entry in
                PlanEntryRow(entry: $entry, onDelete: {
                    withAnimation { planEntries.removeAll { $0.id == entry.id } }
                })
                Divider().overlay(Color.white.opacity(0.05))
            }

            // Add subject manually
            addSubjectRow
        }
    }

    // ── Add subject row ───────────────────────────────────────────────────────

    @State private var addSubjectQuery = ""
    @State private var showAddSubject  = false

    var addSubjectRow: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { showAddSubject.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 12))
                    Text("Add Subject").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 10)

            if showAddSubject {
                Picker("Subject", selection: $addSubjectQuery) {
                    Text("Pick subject…").tag("")
                    ForEach(allSubjects.filter { s in !planEntries.map(\.subject).contains(s) }, id: \.self) { s in
                        Text(s).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                if !addSubjectQuery.isEmpty {
                    Button("Add") {
                        addSubjectToPlan(addSubjectQuery)
                        addSubjectQuery = ""; showAddSubject = false
                    }
                    .buttonStyle(.bordered).tint(accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // ── Raw AI text (collapsed by default) ───────────────────────────────────

    @State private var showRaw = false

    var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { showRaw.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: showRaw ? "chevron.up" : "chevron.down").font(.system(size: 9))
                    Text("Show AI reasoning").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.top, 8)

            if showRaw {
                MarkdownText(rawAIText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // ── Action bar ────────────────────────────────────────────────────────────

    var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(planEntries.count) subjects · \(String(format: "%.1f", planEntries.map(\.hours).reduce(0,+))) total hours")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Text("over \(effectiveDays) day\(effectiveDays == 1 ? "" : "s")")
                    .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()

            if applied {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(applyMessage).font(.system(size: 12)).foregroundColor(.green)
                }
            }

            Button("Apply Plan") {
                applyPlan()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(applied ? Color.green : accent)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(planEntries.isEmpty || applied)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // ── Generate ──────────────────────────────────────────────────────────────

    func generate() {
        guard !selectedSubjects.isEmpty else { return }
        isGenerating = true
        planEntries  = []
        rawAIText    = ""
        applied      = false
        suggestedNewSubjects = []

        let days     = effectiveDays
        let subjects = Array(selectedSubjects).sorted()
        let prompt   = buildPlanPrompt(days: days, subjects: subjects)

        AIService.shared.chat(
            history: [ChatMessage(role: .user, content: prompt)],
            systemPrompt: buildPlanSystemPrompt()
        ) { [self] reply in
            DispatchQueue.main.async {
                self.isGenerating = false
                self.rawAIText    = reply
                self.planEntries  = Self.parseEntries(from: reply, subStore: subStore)
                self.suggestedNewSubjects = Self.parseSuggestions(from: reply,
                    existing: self.planEntries.map(\.subject) + subjects)
            }
        }
    }

    func buildPlanSystemPrompt() -> String {
        """
        You are a study plan generator. Output ONLY a structured plan in this exact format per subject:
        SUBJECT: <name>
        HOURS: <number>
        PRIORITY: <High|Medium|Low>
        NOTE: <one-line reason>

        After all subjects, optionally add:
        SUGGEST: <subject name that should be studied but isn't in the plan>

        Do not add markdown, prose, or explanations outside this format.
        """
    }

    func buildPlanPrompt(days: Int, subjects: [String]) -> String {
        let ctx = SessionStore.shared.fullContextForAI
        let subjectList = subjects.joined(separator: ", ")
        return """
        Create a study plan for the next \(days) day\(days == 1 ? "" : "s").
        Only plan for these subjects (user selected): \(subjectList)

        \(ctx)

        Rules:
        - ONLY include the subjects listed above — do not add others
        - Flag subjects not studied this week with HIGH priority
        - Hours should be realistic for \(days) days total
        - Suggest any important subjects from the list the user might be under-preparing
        """
    }

    // ── Parse AI output → PlanEntry array ────────────────────────────────────

    static func parseEntries(from text: String, subStore: SubjectStore) -> [PlanEntry] {
        var entries: [PlanEntry] = []
        let lines = text.components(separatedBy: "\n")
        var current: [String: String] = [:]

        func flush() {
            guard let name = current["SUBJECT"], !name.isEmpty else { return }
            let hours = Double(current["HOURS"] ?? "1") ?? 1
            let pri   = current["PRIORITY"] ?? "Medium"
            let note  = current["NOTE"] ?? ""
            entries.append(PlanEntry(
                subject : name,
                hours   : max(0.5, min(12, hours)),
                days    : [],
                priority: pri,
                note    : note,
                color   : subStore.color(for: name)
            ))
            current = [:]
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SUBJECT:") {
                flush()
                current["SUBJECT"] = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("HOURS:") {
                current["HOURS"] = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("PRIORITY:") {
                current["PRIORITY"] = String(t.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("NOTE:") {
                current["NOTE"] = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return entries
    }

    static func parseSuggestions(from text: String, existing: [String]) -> [String] {
        text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("SUGGEST:") }
            .map { String($0.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            .filter { s in !existing.contains(where: { $0.lowercased() == s.lowercased() }) }
    }

    // ── Add a subject to the plan ─────────────────────────────────────────────

    func addSubjectToPlan(_ name: String) {
        guard !planEntries.contains(where: { $0.subject == name }) else { return }
        subStore.ensureMeta(for: name)
        planEntries.append(PlanEntry(
            subject: name, hours: 1.0, days: [], priority: "Medium",
            note: "Added manually", color: subStore.color(for: name)
        ))
    }

    // ── Apply plan to SubjectStore weekly goals ───────────────────────────────

    func applyPlan() {
        for entry in planEntries {
            subStore.ensureMeta(for: entry.subject)
            // Distribute hours across the week
            let weeklyHours = entry.hours * (7.0 / Double(max(1, effectiveDays)))
            subStore.setWeeklyGoal(subject: entry.subject, hours: min(40, weeklyHours))
        }
        applied      = true
        applyMessage = "Plan applied to Weekly Goals ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { applied = false }
    }
}

// ── Subject Picker Cell — checkbox tile used in pre-selection screen ──────────

struct SubjectPickerCell: View {
    let subject    : String
    let color      : Color
    let isSelected : Bool
    let sessions   : TimeInterval   // total studied seconds
    let onTap      : () -> Void

    private func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m" : "—"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? color : Color.white.opacity(0.08))
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(subject)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Text(fmtDur(sessions) + " studied")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? color.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// ── Plan Entry Row — single editable row ─────────────────────────────────────

struct PlanEntryRow: View {
    @Binding var entry   : PlanEntry
    let onDelete         : () -> Void
    @Bindable var subStore = SubjectStore.shared
    var priorityColor: Color {
        switch entry.priority {
        case "High":   return .red
        case "Medium": return .orange
        default:       return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Subject
            HStack(spacing: 8) {
                Circle().fill(entry.color).frame(width: 8, height: 8)
                    .shadow(color: entry.color.opacity(0.5), radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.subject)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hours stepper
            HStack(spacing: 6) {
                Button {
                    entry.hours = max(0.5, entry.hours - 0.5)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text(entry.hoursText)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.color)
                    .frame(width: 44, alignment: .center)

                Button {
                    entry.hours = min(12, entry.hours + 0.5)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(entry.color)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 80, alignment: .center)

            // Priority picker
            Menu {
                ForEach(["High", "Medium", "Low"], id: \.self) { p in
                    Button(p) { entry.priority = p }
                }
            } label: {
                Text(entry.priority)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(priorityColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(priorityColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .frame(width: 80, alignment: .center)

            // Delete
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .frame(width: 60, alignment: .center)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
