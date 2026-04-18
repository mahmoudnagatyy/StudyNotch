import SwiftUI
import AppKit

// ── ARCHITECTURE ──────────────────────────────────────────────────────────────
//
//  Window TOP = physical screen top (sf.maxY).
//  ZeroSafeAreaHostingView returns 0 insets so SwiftUI starts at y=0 = screen top.
//  The physical notch hardware occupies the TOP portion of the pill.
//  ► Content in the COLLAPSED view must be bottom-aligned inside the pill.
//  ► Content in EXPANDED views uses Spacer(minLength: notchHeight) to push
//    below the hardware notch.
//
// ─────────────────────────────────────────────────────────────────────────────

struct NotchView: View {
    var timer        = StudyTimer.shared
    var store        = SessionStore.shared
    var modeStore    = ModeStore.shared
    @Bindable var subjectStore = SubjectStore.shared
    var taskStore    = TaskStore.shared
    @Bindable var stageDetector = StageManagerDetector.shared
    @State private var showQuickNotes = false

    static var notchHeight: CGFloat = 37
    static var notchWidth : CGFloat = 160

    @State private var mode    = 0   // 0=collapsed  1=timer  2=analytics
    @State private var pulsing       = false
    @State private var breathe        = false    // idle breathing animation
    @State private var calTimer: Timer? = nil
    var gcal     = GoogleCalendarService.shared
    @Bindable var detector = AutoSessionDetector.shared
    // Stress level: 0=none, 1=warning, 2=critical
    var stressLevel: Int {
        let overdue = taskStore.overdueCount
        if let exam = subjectStore.urgentExam, exam.daysUntil < 1 { return 2 }
        if overdue >= 3 { return 2 }
        if overdue >= 1 { return 1 }
        return 0
    }

    // Momentum: glow intensity increases with streak
    var momentumGlow: Double {
        let s = SessionStore.shared
        let cal = Calendar.current; var n = 0; var day = Date()
        while s.sessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return min(1.0, Double(n) / 10.0)   // max glow at 10-day streak
    }

    // Effective pill shadow color
    var pillShadowColor: Color {
        if timer.state == .running { return dotColor.opacity(0.45) }
        if stressLevel == 2       { return Color.red.opacity(0.5) }
        if stressLevel == 1       { return Color.orange.opacity(0.3) }
        if momentumGlow > 0.3     { return Color.yellow.opacity(momentumGlow * 0.4) }
        return .black.opacity(mode == 0 ? 0 : 0.6)
    }

    var pillShadowRadius: CGFloat {
        if timer.state == .running { return 18 }
        if stressLevel == 2       { return breathe ? 20 : 12 }
        if momentumGlow > 0.3     { return 10 + CGFloat(momentumGlow * 10) }
        return 16
    }
    @State private var showPinManager = false {
        didSet {
            // When popover closes, stay expanded briefly then let normal hover handle it
            if !showPinManager { mode = 1 }
        }
    }
    @State private var pinnedSubjects: [String] = {
        if let saved = UserDefaults.standard.stringArray(forKey: "notch.pinnedSubjects") {
            return saved
        }
        return []   // empty = show knownSubjects.prefix(6) as default
    }()

    // Subject to use for dot color – current session or last saved
    var dotSubject: String {
        if !timer.currentSubject.isEmpty { return timer.currentSubject }
        return store.sessions.first?.subject ?? ""
    }
    var dotColor: Color {
        guard !dotSubject.isEmpty else { return Color.white.opacity(0.5) }
        return subjectStore.color(for: dotSubject)
    }

    var accent: Color {
        switch timer.state {
        case .running: return Color(red: 0.2, green: 1.0, blue: 0.5)
        case .paused:  return Color(red: 1.0, green: 0.85, blue: 0.0)
        case .idle:    return Color.white.opacity(0.5)
        }
    }

    // Dynamic Island style: expands LEFT + RIGHT + DOWN
    // Collapsed: snug around hardware notch
    // Expanded: wider left/right like DI, taller downward
    var pillW: CGFloat {
        switch mode {
        case 2:  return max(NotchView.notchWidth + 180, 380)  // analytics: wide
        case 1:  return max(NotchView.notchWidth + 110, 310)  // timer: wide -> compact
        default: return NotchView.notchWidth                   // collapsed: hardware width
        }
    }
    var pillH: CGFloat {
        switch mode {
        case 2:  return 190 + NotchView.notchHeight + 25
        case 1:  return (timer.state == .idle ? 85 : 165) + NotchView.notchHeight + 25
        default: return NotchView.notchHeight // Completely flush behind the hardware notch
        }
    }

    var topRadius   : CGFloat { mode == 0 ? 0 : 10 }
    var bottomRadius: CGFloat { mode == 0 ? 8 : 26 }

    // Idle breathing scale — very subtle, Apple-like
    var breatheScale: CGFloat {
        guard mode == 0, timer.state == .idle else { return 1.0 }
        return breathe ? 1.012 : 0.998
    }

    // Stress red-pulse opacity for the pill overlay
    var stressOverlayOpacity: Double {
        guard mode == 0 else { return 0 }
        if stressLevel == 2 { return breathe ? 0.22 : 0.08 }
        if stressLevel == 1 { return breathe ? 0.12 : 0.02 }
        return 0
    }

    // Momentum glow scale boost
    var momentumScale: CGFloat {
        guard mode == 0, timer.state == .idle, momentumGlow > 0.3 else { return 1.0 }
        return 1.0 + CGFloat(momentumGlow) * 0.015
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchPillShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(Color.black)
                    .shadow(color: pillShadowColor, radius: pillShadowRadius, y: 8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathe)

                // Stress colour overlay — red/orange glow on the pill itself
                if stressLevel > 0 && mode == 0 {
                    NotchPillShape(topRadius: topRadius, bottomRadius: bottomRadius)
                        .fill(stressLevel == 2 ? Color.red : Color.orange)
                        .opacity(stressOverlayOpacity)
                        .animation(.easeInOut(duration: stressLevel == 2 ? 0.8 : 1.2)
                                    .repeatForever(autoreverses: true), value: breathe)
                }

                // Momentum glow overlay — golden shimmer
                if momentumGlow > 0.3 && mode == 0 && timer.state == .idle {
                    NotchPillShape(topRadius: topRadius, bottomRadius: bottomRadius)
                        .fill(Color.yellow)
                        .opacity(momentumGlow * 0.08)
                }

                if mode == 0      { collapsed }
                else if mode == 1 { 
                    timerPanel
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.easeOut(duration: 0.2).delay(0.05)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        ))
                }
                else              { 
                    analyticsPanel
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.easeOut(duration: 0.2).delay(0.05)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        ))
                }
            }
            .frame(width: pillW, height: pillH)
            // Breathing + momentum scale — only when collapsed and idle
            .scaleEffect(breatheScale * momentumScale)
            .animation(
                mode == 0 && timer.state == .idle
                    ? .easeInOut(duration: stressLevel == 2 ? 0.9 : 2.5).repeatForever(autoreverses: true)
                    : .default,
                value: breathe
            )
            // ── Hover detection ──────────────────────────────────────────────
            // Driven by NotchHoverMonitor (local+global mouse monitor).
            // Enter is instant, exit is debounced inside the monitor.
            .onChange(of: NotchHoverMonitor.shared.isHovering) { _, hovering in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    mode = hovering ? 1 : 0
                }
            }
            .onChange(of: showPinManager) { _, locked in
                NotchHoverMonitor.shared.isLockedExpanded = locked
            }
            .frame(maxWidth: .infinity, alignment: .center)
            // DI-style spring: snappy expand, gentle collapse with overshoot
            .animation(.spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.1), value: mode)
            .animation(.spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.1), value: pillW)
            .animation(.spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.1), value: pillH)

            Spacer()
        }
        // Centre-align pill horizontally, and rigorously bind top to the screen hardware top
        // preventing AppKit from centering the intrinsic 38px height inside the 320px NSWindow
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: StageManagerDetector.shared.isActive) { _, active in
            _ = active
        }
        .onAppear {
            // Seed color metas and current subject from last session on launch
            for s in store.knownSubjects { subjectStore.ensureMeta(for: s) }
            if timer.currentSubject.isEmpty, let last = store.sessions.first {
                timer.currentSubject = last.subject
            }
            // Start idle breathing animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { breathe = true }
            }
            // Start auto session detector
            if AutoSessionDetector.shared.isEnabled {
                AutoSessionDetector.shared.start()
            }
            // Fetch today's calendar events for notch display
            if GoogleCalendarService.shared.isConnected {
                GoogleCalendarService.shared.fetchTodayEvents()
            }
            // Refresh calendar events every hour
            calTimer?.invalidate()
            calTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                if GoogleCalendarService.shared.isConnected {
                    GoogleCalendarService.shared.fetchTodayEvents()
                }
            }
            // Check spaced repetition reminders
            SpacedRepetitionService.shared.checkAndSchedule()
        }
    }

    // ── Collapsed ─────────────────────────────────────────────────────────────
    //  The physical notch hardware covers the TOP of the pill.
    //  We use a VStack with Spacer on top so content sits at the BOTTOM
    //  of the pill — the part that sticks out below the hardware.

    var collapsed: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Inner rim glow — subtle white highlight at top of pill
            LinearGradient(
                colors: [Color.white.opacity(pulsing ? 0.10 : 0.05), .clear],
                startPoint: .top, endPoint: .center
            )
            .frame(height: 8)
            .allowsHitTesting(false)

            HStack(spacing: 5) {
                // Seasonal icon
                if !ThemeService.shared.currentSeason.emoji.isEmpty {
                    Text(ThemeService.shared.currentSeason.emoji)
                        .font(.system(size: 9))
                        .opacity(0.8)
                }

                // Pulsing subject-colour dot with bloom
                ZStack {
                    if pulsing || momentumGlow > 0.4 {
                        Circle()
                            .fill(dotColor.opacity(0.25))
                            .blur(radius: 4)
                            .frame(width: 14, height: 14)
                            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulsing)
                    }
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: dotColor, radius: pulsing ? 6 : breathe ? 2.5 : 1.5)
                        .scaleEffect(pulsing ? 1.4 : breathe ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulsing)
                        .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: breathe)
                }
                .onChange(of: timer.state) { state in pulsing = (state == .running) }

                // Label
                if timer.state == .idle, let exam = subjectStore.urgentExam {
                    HStack(spacing: 3) {
                        Image(systemName: "alarm.fill").font(.system(size: 7)).foregroundColor(.orange)
                        Text("\(exam.subject.prefix(6)) · \(exam.pillText)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                } else if timer.state != .idle {
                    HStack(spacing: 4) {
                        Text(timer.formattedTime)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: timer.formattedTime)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(LinearGradient(
                                colors: [.white, dotColor.opacity(0.85)],
                                startPoint: .leading, endPoint: .trailing))
                        if !timer.currentSubject.isEmpty {
                            Text("·").font(.system(size: 9)).foregroundColor(.white.opacity(0.25))
                            Text(String(timer.currentSubject.prefix(6)))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(dotColor.opacity(0.85))
                        }
                    }
                } else {
                    let nextEvent = GoogleCalendarService.shared.todayEvents
                        .first { ($0.startTime ?? .distantPast) > Date() }
                    if let ev = nextEvent {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar").font(.system(size: 7))
                                .foregroundColor(Color(red:0.25,green:0.72,blue:1).opacity(0.8))
                            Text(ev.subject.prefix(8) + " " + ev.timeLabel)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(red:0.25,green:0.72,blue:1).opacity(0.9))
                        }
                    } else {
                        Text("Study")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }

                // Right badge
                if timer.state == .idle {
                    if taskStore.overdueCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 7, weight: .bold))
                            Text("\(taskStore.overdueCount)").font(.system(size: 8, weight: .bold))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: taskStore.overdueCount)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red.opacity(0.18)).clipShape(Capsule())
                    } else if taskStore.pendingCount > 0 {
                        Text("\(taskStore.pendingCount)")
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: taskStore.pendingCount)
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.28))
                    } else {
                        Text("LV\(GamificationStore.shared.currentLevel.number)")
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: GamificationStore.shared.currentLevel.number)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.yellow.opacity(0.8))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.15)).clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 3)
        }
    }

    // ── Auto-detect suggestion banner ────────────────────────────────────────

    var autoDetectBanner: some View {
        Group {
            if let sug = detector.suggestion, timer.state == .idle {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(sug.emoji).font(.system(size: 12))
                        Text("Looks like you're studying \(sug.subject)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Button("Start Session") {
                            detector.acceptSuggestion()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(subjectStore.color(for: sug.subject))
                        .clipShape(Capsule())

                        Button("Not now") {
                            detector.dismissSuggestion()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // ── Timer panel (mode == 1) ───────────────────────────────────────────────

    var timerPanel: some View {
        VStack(spacing: 3) {
            Color.clear.frame(height: NotchView.notchHeight + 25)

            // Auto-detect suggestion
            if let sug = detector.suggestion, timer.state == .idle {
                autoDetectBanner
            }
            // Subject strip — quick-select when idle, label when running
            if timer.state == .idle {
                subjectStrip
                // Pomodoro presets — quick-start timed sessions
                pomodoroPresets
            } else if !timer.currentSubject.isEmpty {
                HStack(spacing: 5) {
                    Circle()
                        .fill(subjectStore.color(for: timer.currentSubject))
                        .frame(width: 6, height: 6)
                        .shadow(color: subjectStore.color(for: timer.currentSubject), radius: 4)
                    Text(timer.currentSubject)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                    if let exam = subjectStore.urgentExam(for: timer.currentSubject) {
                        Text("· \(exam.pillText)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    // Target time remaining
                    if let target = timer.targetDuration {
                        let remaining = max(0, target - timer.elapsed)
                        Text("· \(fmtMins(remaining)) left")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                }
            }

            // Timer digits — large, glowing when running
            HStack(spacing: 8) {
                ZStack {
                    // Glow halo behind dot when running
                    if timer.state == .running {
                        Circle()
                            .fill(accent.opacity(0.35))
                            .blur(radius: 5)
                            .frame(width: 16, height: 16)
                    }
                    // Pomodoro progress ring
                    if let target = timer.targetDuration, target > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(min(timer.elapsed / target, 1.0)))
                            .stroke(accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 18, height: 18)
                            .rotationEffect(.degrees(-90))
                    }
                    Circle().fill(accent).frame(width: 7, height: 7)
                        .shadow(color: accent, radius: timer.state == .running ? 5 : 0)
                }

                Text(timer.formattedTime)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: timer.formattedTime)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        timer.state == .running
                            ? LinearGradient(colors: [.white, accent.opacity(0.9)],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.white, .white], startPoint: .leading, endPoint: .trailing)
                    )
            }

            // Status pill — tappable
            Button { timer.toggle() } label: {
                HStack(spacing: 6) {
                    Text(timer.state == .idle    ? "Ready to start"
                       : timer.state == .running ? "Studying…" : "Paused")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    if !timer.distractions.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.slash").font(.system(size: 7))
                            Text("\(timer.distractions.count)").font(.system(size: 8, weight: .bold))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: timer.distractions.count)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2)).clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(timer.state == .running ? "Tap to pause" : "Tap to start")

            if timer.state != .idle && !timer.currentSubject.isEmpty {
                sessionTaskStrip
            }

            // ── Ambient Sounds ────────────────────────────────────────────
            if timer.state != .idle {
                ambientSoundsPicker
            }

            // Button row — with coloured backgrounds on key actions
            HStack(spacing: 0) {
                tb(timer.state == .running ? "pause.fill" : "play.fill", accent) { timer.toggle() }
                tb("stop.fill",            .white.opacity(0.45)) { doFinish() }
                tb("bolt.slash.fill",      timer.distractions.isEmpty ? .white.opacity(0.45) : .orange) { logDistraction() }
                // Quick notes button (replaces split screen)
                tb("note.text",            timer.sessionNotes.isEmpty ? .white.opacity(0.45) : .cyan) {
                    showQuickNotes.toggle()
                }
                tb("chart.bar.fill",       .white.opacity(0.45)) { withAnimation { mode = 2 } }
            }

            // Quick notes popover
            if showQuickNotes && timer.state != .idle {
                quickNotesField
            }

            if timer.state != .idle && !showQuickNotes {
                TelegramQuickNoteField()
            }
        }
        .padding(.horizontal, 10)
    }

    // ── Pomodoro presets ──────────────────────────────────────────────────────

    var pomodoroPresets: some View {
        HStack(spacing: 4) {
            ForEach([25, 45, 60, 90], id: \.self) { mins in
                Button {
                    timer.startWithTarget(mins)
                } label: {
                    Text("\(mins)m")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.85))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Start \(mins)-minute Pomodoro session")
            }
            // Free mode (no target)
            Button {
                timer.start()
            } label: {
                Text("∞")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Start free session (no time limit)")
        }
        .frame(height: 18)
    }

    // ── Quick notes field ─────────────────────────────────────────────────────

    var quickNotesField: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 9))
                .foregroundColor(.cyan.opacity(0.7))
            TextField("Quick note…", text: Binding(
                get: { timer.sessionNotes },
                set: { timer.sessionNotes = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.85))
            Button {
                showQuickNotes = false
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.cyan.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.15), lineWidth: 0.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    func fmtMins(_ d: TimeInterval) -> String {
        let m = Int(d) / 60; let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }

    var ambientSoundsPicker: some View {
        HStack(spacing: 8) {
            ForEach(AmbientSoundType.allCases) { type in
                if type != .none {
                    Button {
                        AmbientSoundService.shared.toggle(type)
                    } label: {
                        Text(type.rawValue.prefix(1))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AmbientSoundService.shared.currentSound == type ? .white : .white.opacity(0.4))
                            .frame(width: 18, height: 18)
                            .background(AmbientSoundService.shared.currentSound == type ? Color.purple.opacity(0.6) : Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Toggle \(type.rawValue) background sound")
                }
            }
            
            if AmbientSoundService.shared.isPlaying {
                // Mini volume slider
                Slider(value: Binding(
                    get: { Double(AmbientSoundService.shared.volume) },
                    set: { AmbientSoundService.shared.volume = Float($0) }
                ), in: 0...1)
                .controlSize(.mini)
                .frame(width: 60)
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // ── Tasks for current session subject ────────────────────────────────────
    //  Shows up to 3 pending tasks for the subject being studied.
    //  Tap the circle to mark complete — awards XP immediately.

    var sessionTaskStrip: some View {
        let pending = taskStore.pending(for: timer.currentSubject).prefix(3)
        return Group {
            if !pending.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(pending)) { task in
                        HStack(spacing: 6) {
                            // Completion circle
                            Button {
                                taskStore.complete(task)
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(task.isOverdue ? Color.red.opacity(0.7)
                                              : task.dueSoon  ? Color.orange.opacity(0.7)
                                              : Color.white.opacity(0.3),
                                                lineWidth: 1)
                                        .frame(width: 12, height: 12)
                                    if task.isCompleted {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            // Task title
                            Text(task.title)
                                .font(.system(size: 9))
                                .foregroundColor(task.isOverdue ? .red.opacity(0.9)
                                               : task.dueSoon  ? .orange.opacity(0.9)
                                               : .white.opacity(0.65))
                                .lineLimit(1)

                            Spacer()

                            // Priority badge
                            if task.priority == .high {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.red.opacity(0.7))
                            }

                            // Due date
                            if let due = task.dueDate {
                                Text(due.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.25))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 2)
            }
        }
    }

    // ── Subject quick-select strip ────────────────────────────────────────────

    var displayedSubjects: [String] {
        if pinnedSubjects.isEmpty { return [] }
        let all = Array(Set(store.knownSubjects + subjectStore.metas.map { $0.name }))
        return pinnedSubjects.filter { all.contains($0) }
    }

    var subjectStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    // ── Spin the Wheel button ─────────────────────────────────
                    Button {
                        spinTheWheel()
                    } label: {
                        Text("🎲")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 22)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Feeling lucky? Pick a random subject")

                    ForEach(displayedSubjects, id: \.self) { sub in
                        let sel = timer.currentSubject == sub
                        Button {
                            timer.currentSubject = sub
                            subjectStore.ensureMeta(for: sub)
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(subjectStore.color(for: sub)).frame(width: 5, height: 5)
                                Text(sub)
                                    .font(.system(size: 9, weight: sel ? .bold : .regular))
                                    .foregroundColor(sel ? .white : .white.opacity(0.45))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(sel ? subjectStore.color(for: sub).opacity(0.2) : Color.white.opacity(0.07))
                            .clipShape(Capsule())
                            .overlay { if sel { Capsule().stroke(subjectStore.color(for: sub).opacity(0.5), lineWidth: 0.5) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Edit pinned subjects button
            Button {
                showPinManager = true
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Edit pinned subjects")
            .popover(isPresented: $showPinManager, arrowEdge: .bottom) {
                PinManagerPopover(pinnedSubjects: $pinnedSubjects)
            }
        }
        .frame(height: 22)
    }

    // ── Spin the Wheel — cryptographically random pick from pinned subjects ─────
    func spinTheWheel() {
        let all = Array(Set(store.knownSubjects + subjectStore.metas.map { $0.name }))
        var candidates = pinnedSubjects.isEmpty ? all : pinnedSubjects.filter { all.contains($0) }
        candidates = dedupSubjects(candidates)
        guard !candidates.isEmpty else { return }

        // Avoid immediate repeats when possible so rolls feel genuinely random
        if candidates.count > 1 {
            let current = norm(timer.currentSubject)
            let nonCurrent = candidates.filter { norm($0) != current }
            if !nonCurrent.isEmpty { candidates = nonCurrent }
        }

        guard let winner = candidates.randomElement() else { return }

        // Roulette animation — 12 rapid flashes, each picks a truly random subject
        let totalFlashes = Int.random(in: 12...18)
        var flashes = 0

        func flash() {
            guard flashes < totalFlashes else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    timer.currentSubject = winner
                    subjectStore.ensureMeta(for: winner)
                }
                return
            }
            guard let rolling = candidates.randomElement() else { return }
            withAnimation(.easeIn(duration: 0.04)) {
                timer.currentSubject = rolling
                subjectStore.ensureMeta(for: rolling)
            }
            flashes += 1
            // Exponential slowdown with small random jitter
            let base = 0.045 * pow(1.17, Double(flashes))
            let jitter = Double.random(in: 0.0...0.018)
            let delay = base + jitter
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { flash() }
        }
        flash()
    }

    private func dedupSubjects(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(norm($0)).inserted }
    }

    private func norm(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ── Mini analytics panel (mode == 2) ──────────────────────────────────────

    var analyticsPanel: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: NotchView.notchHeight + 25)
            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.38))
                Spacer()
                Text(dur(store.todayTotal))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.todayTotal)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 1, blue: 0.5))
                Button { withAnimation { mode = 1 } } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain).padding(.leading, 8)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 7)

            Divider().overlay(Color.white.opacity(0.08))

            if store.subjectTotals.isEmpty {
                Spacer()
                Text("No sessions yet").font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.28))
                Spacer()
            } else {
                VStack(spacing: 7) {
                    ForEach(store.subjectTotals.prefix(3), id: \.subject) { s in
                        miniBar(s.subject, s.total, store.subjectTotals[0].total)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                Button {
                    AnalyticsWindowController.show()
                    withAnimation { mode = 0 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill").font(.system(size: 9))
                        Text("Analytics").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.42))
                    .frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().frame(height: 18).overlay(Color.white.opacity(0.08))

                Button {
                    AIChatWindowController.show()
                    withAnimation { mode = 0 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile").font(.system(size: 9))
                        Text("AI Chat").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.42))
                    .frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    func miniBar(_ name: String, _ val: TimeInterval, _ mx: TimeInterval) -> some View {
        let r = CGFloat(val / mx)
        let c = subjectStore.color(for: name)
        return HStack(spacing: 8) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(name).font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(1).frame(width: 74, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                    Capsule().fill(c).frame(width: g.size.width * r, height: 5)
                }
            }
            .frame(height: 5)
            Text(dur(val)).font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.38)).frame(width: 32, alignment: .trailing)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func tb(_ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 42, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func logDistraction() {
        guard timer.state == .running else { return }
        let labels = ["📱 Phone", "💬 Social", "💭 Mind wandered", "🔊 Noise", "Other"]
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "Log Distraction"
            alert.informativeText = "What distracted you?"
            for l in labels { alert.addButton(withTitle: l) }
            alert.addButton(withTitle: "Cancel")
            let idx = alert.runModal().rawValue - 1000
            if idx >= 0 && idx < labels.count {
                StudyTimer.shared.logDistraction(label: labels[idx])
            }
        }
    }

    func doFinish() {
        // Capture subject BEFORE finish() calls reset() which clears currentSubject
        let subject = StudyTimer.shared.currentSubject
        if let d = StudyTimer.shared.finish() {
            withAnimation { mode = 0 }
            SessionEndWindowController.present(sessionData: d, preselectedSubject: subject)
        }
    }

    func dur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600, m = (Int(d) % 3600)/60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m" : "\(Int(d))s"
    }
}

// ── Custom pill shape ─────────────────────────────────────────────────────────

struct NotchPillShape: Shape {
    var topRadius   : CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let tr = topRadius; let br = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                              radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        if tr > 0 { p.addArc(center: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                              radius: tr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        p.closeSubpath()
        return p
    }
}

// ── NSPanel ───────────────────────────────────────────────────────────────────

class NotchPanel: NSPanel {
    override var canBecomeKey : Bool { true  }
    override var canBecomeMain: Bool { false }
}

// ── Zero safe area hosting view ───────────────────────────────────────────────

class ZeroSafeAreaHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

// ── Notch Hover Monitor ───────────────────────────────────────────────────────
//
//  Hover solution for notch-dwelling macOS apps.
//
//  • Panel starts with ignoresMouseEvents = TRUE  → clicks pass through
//  • A global + local mouse monitor checks cursor vs pill rect
//  • ENTER is instant.  EXIT is debounced (0.3s) to absorb the spurious
//    mouse events macOS generates when ignoresMouseEvents toggles.
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class NotchHoverMonitor {
    static let shared = NotchHoverMonitor()

    var isHovering: Bool = false
    var isLockedExpanded: Bool = false {
        didSet {
            if isLockedExpanded {
                isHovering = true
                panel?.ignoresMouseEvents = false
                exitWorkItem?.cancel()
            } else {
                evaluate()
            }
        }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var panel: NSPanel?
    private var exitWorkItem: DispatchWorkItem?

    /// Start monitoring. Call once after the panel is set up.
    func start(panel: NSPanel) {
        self.panel = panel

        // Global monitor — fires when OTHER apps are active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluate()
        }

        // Local monitor — fires when THIS app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluate()
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor  = nil }
        exitWorkItem?.cancel()
    }

    deinit { stop() }

    /// Core logic: is the mouse inside the pill?
    private func evaluate() {
        guard !isLockedExpanded else { return }
        guard let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let sf    = screen.frame

        // Pill is horizontally centred on screen, at the very top.
        // When collapsed, use the notch hardware rect.
        // When expanded, use a larger rect so the user can interact
        // with buttons inside the expanded panel.
        let expanded = isHovering
        let w: CGFloat = expanded
            ? max(NotchView.notchWidth + 180, 380)  // expanded: full panel width
            : NotchView.notchWidth + 10             // collapsed: tight around hardware notch
        let h: CGFloat = expanded
            ? 220 + NotchView.notchHeight           // expanded: max expected height
            : NotchView.notchHeight + 10            // invisible hit box slightly below the notch
        let x = sf.midX - w / 2
        let y = sf.maxY - h
        
        let pillRect = CGRect(x: x, y: y, width: w, height: h)
        let inside   = pillRect.contains(mouse)

        if inside && !isHovering {
            // ── ENTER: immediate ─────────────────────────────────────────
            exitWorkItem?.cancel()
            exitWorkItem = nil
            isHovering = true
            panel?.ignoresMouseEvents = false
        } else if !inside && isHovering {
            // ── EXIT: debounced ──────────────────────────────────────────
            // Cancel any pending exit first (idempotent)
            exitWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // Re-check position one final time before actually exiting
                let finalMouse = NSEvent.mouseLocation
                let finalRect  = CGRect(x: x, y: y, width: w, height: h)
                guard !finalRect.contains(finalMouse) else { return }

                self.isHovering = false
                self.panel?.ignoresMouseEvents = true
            }
            exitWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
    }
}

// ── Window controller ─────────────────────────────────────────────────────────

class NotchWindowController: NSWindowController {
    static var shared: NotchWindowController?

    static func show() {
        guard shared == nil else { return }
        shared = NotchWindowController()
        shared?.showWindow(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shared?.positionPanel()
        }
    }

    convenience init() {
        let panelH: CGFloat = 320
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: panelH),
            styleMask: NSWindow.StyleMask(rawValue:
                NSWindow.StyleMask.borderless.rawValue | (1 << 7)),
            backing: .buffered, defer: false
        )
        panel.backgroundColor        = NSColor.clear
        panel.isOpaque               = false
        panel.hasShadow              = false
        panel.isFloatingPanel        = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents     = true

        // ── KEY: start with mouse events ignored so clicks pass to apps below
        panel.ignoresMouseEvents = true

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

        self.init(window: panel)

        let host = ZeroSafeAreaHostingView(rootView: NotchView())
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        positionPanel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(positionPanel),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Start the hover monitor
        NotchHoverMonitor.shared.start(panel: panel)
    }

    @objc func positionPanel() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let sf = screen.frame
        let notchH: CGFloat
        let notchW: CGFloat
        if #available(macOS 12.0, *) {
            let topInset = screen.safeAreaInsets.top
            notchH = topInset > 0 ? topInset : NSStatusBar.system.thickness
            let l = screen.safeAreaInsets.left
            let r = screen.safeAreaInsets.right
            notchW = (l > 0 && r > 0) ? sf.width - l - r : 162
        } else {
            notchH = NSStatusBar.system.thickness
            notchW = 0
        }
        NotchView.notchHeight = notchH
        NotchView.notchWidth  = notchW

        StageManagerDetector.shared.refresh()

        let panelW = sf.width
        let panelH = panel.frame.height
        panel.setFrame(CGRect(x: sf.minX, y: sf.maxY - panelH,
                              width: panelW, height: panelH), display: true)
    }
}

