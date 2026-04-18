import Foundation
import AppKit
import ApplicationServices
import SwiftUI
import Observation

// ══════════════════════════════════════════════════════════════════════════════
//  AutoSessionDetector.swift
//  StudyNotch
//
//  Polls the frontmost application every 5 seconds to detect study activity.
//  Three sensitivity tiers control how quickly a suggestion fires:
//
//    INSTANT  (5 s)  — Academic folder in Finder, any PDF viewer
//    FAST     (20 s) — Any browser
//    NORMAL   (60 s) — VS Code, Word, Terminal, and other study apps
//
//  FIX LOG (v2):
//  • `poll()` was running on the timer's background-thread delivery in some
//    OS versions. All UI mutations are now gated with `DispatchQueue.main.async`
//    and the timer is explicitly added to `.common` run-loop mode so it fires
//    even during scroll / drag.
//  • `getWindowTitle()` force-cast (`win as! AXUIElement`) would crash if the
//    AX attribute returned an unexpected type. Now uses safe `guard let` cast.
//  • `matchSubject` abbreviation matching was using `prefix(4)` on the window
//    title combined string, not on the subject name — subject-name abbreviation
//    was never actually checked. Fixed.
//  • Cooldown was checked BEFORE dwell tracking, so switching away and back
//    within the cooldown window silently reset the dwell clock, meaning a
//    suggestion could be permanently suppressed. Fixed ordering.
//  • `isEnabled` init read from UserDefaults before `start()` was safe to call;
//    moved startup to `applicationDidFinishLaunching` guidance below.
//  • Added `snooze(minutes:)` so the UI can offer a "Remind me in 5 min" action.
//  • Poll interval is now a settable property so tests can speed it up.
// ══════════════════════════════════════════════════════════════════════════════

@Observable
final class AutoSessionDetector {

    // MARK: Singleton

    static let shared = AutoSessionDetector()

    // MARK: Public state

    private(set) var suggestion: SessionSuggestion? = nil

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "autoDetect.enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "autoDetect.enabled")
            isEnabled ? start() : stop()
        }
    }

    var ignoreList: [String] {
        get { UserDefaults.standard.stringArray(forKey: "autoDetect.ignoreList") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "autoDetect.ignoreList") }
    }

    /// Poll interval in seconds. Default = 5. Lower values improve
    /// responsiveness at the cost of slightly more CPU. Minimum: 2 s.
    var pollInterval: TimeInterval = 5 {
        didSet {
            if pollTimer != nil { start() }   // restart with new interval
        }
    }

    private let browserBundles: Set<String> = ["com.google.Chrome", "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi"]

    // MARK: Session Suggestion model

    struct SessionSuggestion: Identifiable, Equatable {
        let id          = UUID()
        let subject     : String
        let appName     : String
        let windowTitle : String
        let confidence  : Double
        let trigger     : TriggerReason

        var emoji: String {
            switch trigger {
            case .academicFolder: return "📁"
            case .pdfOpened:      return "📄"
            case .browserOpened:  return "🌐"
            case .genericStudy:   return confidence >= 0.8 ? "🎯" : "💡"
            }
        }

        var reasonText: String {
            switch trigger {
            case .academicFolder: return "You opened \"\(windowTitle)\" in Finder"
            case .pdfOpened:      return "You opened a PDF in \(appName)"
            case .browserOpened:  return "You're browsing — looks like study time"
            case .genericStudy:   return "You're using \(appName)"
            }
        }

        // Equatable — treat two suggestions as equal if same subject + trigger
        static func == (lhs: SessionSuggestion, rhs: SessionSuggestion) -> Bool {
            lhs.subject == rhs.subject && lhs.trigger == rhs.trigger
        }
    }

    enum TriggerReason: CaseIterable {
        case academicFolder, pdfOpened, browserOpened, genericStudy
    }

    // MARK: Dwell thresholds (seconds)

    private let dwellInstant: Double = 5
    private let dwellFast   : Double = 20
    private let dwellNormal : Double = 60

    /// How long before the same subject can be suggested again.
    private let cooldownDuration: Double = 600   // 10 minutes

    // MARK: Internal state

    private var pollTimer       : Timer?
    private var candidateSubject: String?
    private var candidateSince  : Date?
    private var candidateTrigger: TriggerReason = .genericStudy
    private var lastSuggested   : [String: Date] = [:]

    // MARK: App lists

    /// Add folder name substrings here (case-insensitive) to trigger instantly.
    var academicFolderPatterns: [String] = [
        "second term", "first term", "third term",
        "semester 1",  "semester 2",  "semester 3",
        "fall 20",     "spring 20",   "summer 20",
        "lectures",    "lecture notes",
        "study materials", "study material",
        "assignments",  "homework",
        "exam prep",    "revision",
        "coursework",   "modules",
        "uni files",    "college",     "university",
    ]

    private let pdfApps: Set<String> = [
        "com.apple.Preview",
        "com.adobe.Reader",
        "net.sourceforge.skim-app.skim",
        "com.readdle.PDFExpert-Mac",
        "com.adobe.acrobat.pro",
    ]

    private let browserApps: Set<String> = [
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.arc-browser.arc",
    ]

    private let genericStudyApps: Set<String> = [
        "com.microsoft.Word",
        "com.microsoft.Powerpoint",
        "com.microsoft.Excel",
        "com.microsoft.OneNote",
        "com.apple.finder",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "com.microsoft.VSCode",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.notion.id",
        "md.obsidian",
        "com.logseq.logseq",
        "com.reeder.3.mac.readkit",   // ReadKit / RSS readers
    ]

    private let studyKeywords: [String] = [
        "lecture", "lct", "sheet", "chapter", "textbook", "study",
        "notes", "tutorial", "assignment", "homework", "exam", "quiz",
        "slides", "problem set", "practice", "review", "revision",
        "worksheet", "syllabus", "course", "module", "week",
        "lab", "midterm", "final",
    ]

    // MARK: Lifecycle

    /// Do NOT call start() inside init — call it from AppDelegate after the
    /// app is fully launched to avoid racing against other singletons.
    private init() {}

    func start() {
        stop()
        let t = Timer(timeInterval: max(2, pollInterval), repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common mode keeps the timer firing during scrolls / modal sheets
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        resetCandidate()
    }

    // MARK: User actions

    func acceptSuggestion() {
        guard let s = suggestion else { return }
        StudyTimer.shared.currentSubject = s.subject
        SubjectStore.shared.ensureMeta(for: s.subject)
        StudyTimer.shared.start()
        clearSuggestion()
    }

    func dismissSuggestion() {
        if let s = suggestion { lastSuggested[s.subject] = Date() }
        clearSuggestion()
    }

    /// Remind again after `minutes` without updating the cooldown timestamp.
    func snoozeSuggestion(minutes: Double = 5) {
        if let s = suggestion {
            // Set cooldown to expire at `now + minutes` instead of `now + cooldownDuration`
            lastSuggested[s.subject] = Date().addingTimeInterval(
                minutes * 60 - cooldownDuration
            )
        }
        clearSuggestion()
    }

    func logManualSession() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID    = frontApp.bundleIdentifier ?? ""
        let appName     = frontApp.localizedName ?? ""
        let windowTitle = getWindowTitle(for: frontApp) ?? ""
        
        let sub = matchSubject(
            windowTitle: windowTitle,
            appName: appName,
            trigger: .genericStudy
        ) ?? SubjectStore.shared.metas.first?.name ?? "General"
        
        suggestion = SessionSuggestion(
            subject: sub,
            appName: appName,
            windowTitle: windowTitle,
            confidence: 1.0,
            trigger: .genericStudy
        )
        acceptSuggestion()
    }

    // MARK: Private — poll

    private func poll() {
        // If a session is already running, hide any lingering banner
        guard StudyTimer.shared.state == .idle else {
            DispatchQueue.main.async { self.suggestion = nil }
            return
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let bundleID    = frontApp.bundleIdentifier ?? ""
        let appName     = frontApp.localizedName ?? ""
        let windowTitle = getWindowTitle(for: frontApp) ?? ""

        // Check Ignore List
        let ignores = ignoreList
        if ignores.contains(bundleID) || ignores.contains(appName) || ignores.contains(where: { !$0.isEmpty && windowTitle.contains($0) }) {
            resetCandidate()
            return
        }

        // ── Classify into a trigger tier ──────────────────────────────────────

        let trigger       : TriggerReason
        let requiredDwell : Double

        if isAcademicFolderOpen(bundleID: bundleID, windowTitle: windowTitle) {
            trigger       = .academicFolder
            requiredDwell = dwellInstant
        } else if pdfApps.contains(bundleID) {
            trigger       = .pdfOpened
            requiredDwell = dwellInstant
        } else if browserApps.contains(bundleID) {
            trigger       = .browserOpened
            requiredDwell = dwellFast
        } else if genericStudyApps.contains(bundleID)
                    || bundleID.contains("education")
                    || bundleID.contains("study") {
            trigger       = .genericStudy
            requiredDwell = dwellNormal
        } else {
            resetCandidate()
            return
        }

        // ── Resolve a subject name ────────────────────────────────────────────

        guard let subject = matchSubject(windowTitle: windowTitle,
                                          appName: appName,
                                          trigger: trigger)
                            ?? bestDefaultSubject()
        else {
            resetCandidate()
            return
        }

        // ── Dwell tracking ────────────────────────────────────────────────────
        // FIX: Track dwell BEFORE cooldown check so switching away and back
        //      doesn't silently reset the clock after cooldown has passed.

        if candidateSubject == subject {
            let elapsed = Date().timeIntervalSince(candidateSince ?? Date())

            guard elapsed >= requiredDwell else { return }
            guard suggestion == nil        else { return }   // banner already shown

            // ── Cooldown check ────────────────────────────────────────────────
            if let last = lastSuggested[subject],
               Date().timeIntervalSince(last) < cooldownDuration { return }

            let confidence = calculateConfidence(windowTitle: windowTitle,
                                                  bundleID: bundleID,
                                                  trigger: trigger)
            let s = SessionSuggestion(
                subject    : subject,
                appName    : appName,
                windowTitle: String(windowTitle.prefix(70)),
                confidence : confidence,
                trigger    : trigger
            )
            DispatchQueue.main.async { self.suggestion = s }

        } else {
            // New candidate — start the dwell clock
            candidateSubject = subject
            candidateSince   = Date()
            candidateTrigger = trigger
        }
    }

    // MARK: Private — helpers

    private func isAcademicFolderOpen(bundleID: String, windowTitle: String) -> Bool {
        guard bundleID.contains("finder") else { return false }
        let title = windowTitle.lowercased()
        return academicFolderPatterns.contains { title.contains($0) }
    }

    private func matchSubject(windowTitle: String,
                               appName: String,
                               trigger: TriggerReason) -> String? {
        let combined = (windowTitle + " " + appName).lowercased()
        let subjects = SessionStore.shared.knownSubjects

        // 1. Direct substring match against known subject names
        for subject in subjects {
            if combined.contains(subject.lowercased()) { return subject }
        }

        // 2. FIX: Abbreviation — first 4 chars of the SUBJECT name (not combined)
        for subject in subjects {
            let abbr = subject.lowercased().prefix(4)
            if abbr.count >= 4 && combined.contains(abbr) { return subject }
        }

        // 3. For academic-folder trigger, check folder name against subjects
        if trigger == .academicFolder {
            let folderLow = windowTitle.lowercased()
            for subject in subjects {
                if folderLow.contains(subject.lowercased()) { return subject }
            }
        }

        // 4. Study-keyword fallback — suggest most-studied subject
        let hasKeyword = studyKeywords.contains { combined.contains($0) }
        return hasKeyword ? SessionStore.shared.subjectTotals.first?.subject : nil
    }

    private func bestDefaultSubject() -> String? {
        SessionStore.shared.subjectTotals.first?.subject
    }

    private func calculateConfidence(windowTitle: String,
                                     bundleID: String,
                                     trigger: TriggerReason) -> Double {
        var base: Double
        switch trigger {
        case .academicFolder: base = 0.90
        case .pdfOpened:      base = 0.85
        case .browserOpened:  base = 0.55
        case .genericStudy:   base = 0.45
        }

        let titleLow    = windowTitle.lowercased()
        let keywordHits = studyKeywords.filter { titleLow.contains($0) }.count
        return min(1.0, base + Double(keywordHits) * 0.05)
    }

    /// FIX: Safe AX window title — no force-cast, graceful nil return.
    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let axApp    = AXUIElementCreateApplication(app.processIdentifier)
        var winRef   : CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &winRef
        ) == .success,
        let winRef,
        CFGetTypeID(winRef) == AXUIElementGetTypeID()
        else { return nil }
        let win = unsafeBitCast(winRef, to: AXUIElement.self)

        var titleRef : CFTypeRef?
        guard AXUIElementCopyAttributeValue(win,
                                            kAXTitleAttribute as CFString,
                                            &titleRef) == .success
        else { return nil }

        return titleRef as? String
    }

    private func resetCandidate() {
        candidateSubject = nil
        candidateSince   = nil
    }

    private func clearSuggestion() {
        DispatchQueue.main.async { self.suggestion = nil }
        resetCandidate()
    }
}

// MARK: - AutoSessionSuggestionBanner (SwiftUI)

/// Compact non-intrusive banner. Wire into NotchWindow.swift via `.overlay`.
/// See `NotchWindow_AutoSuggestion_Patch.swift` for exact integration steps.
struct AutoSessionSuggestionBanner: View {
    let suggestion : AutoSessionDetector.SessionSuggestion
    let onAccept   : () -> Void
    let onDismiss  : () -> Void
    /// Optional: pass a closure for "Remind me later"
    var onSnooze   : (() -> Void)? = nil

    @State private var appeared = false

    private var accentColor: Color {
        SubjectStore.shared.color(for: suggestion.subject)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Colour accent bar
            Rectangle()
                .fill(LinearGradient(
                    colors: [accentColor.opacity(0.9), accentColor.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing))
                .frame(height: 3)

            HStack(spacing: 14) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Text(suggestion.emoji).font(.title2)
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text("Are you studying \(suggestion.subject)?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(suggestion.reasonText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Buttons
                HStack(spacing: 6) {
                    if let snooze = onSnooze {
                        Button(action: snooze) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(5)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Remind me in 5 minutes")
                    }

                    Button { withAnimation { onAccept() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Start")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button { withAnimation { onDismiss() } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(5)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.30), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}
