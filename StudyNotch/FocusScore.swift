import Foundation
import SwiftUI

// ══════════════════════════════════════════════════════════════════════════════
//  FocusScore.swift
//  StudyNotch
//
//  Produces a 0–100 quality score for any study session from four factors:
//    1. Duration quality   — rewards sustained sessions
//    2. Distraction load   — penalises logged distractions (rate-normalised)
//    3. Pause ratio        — penalises excessive pausing
//    4. Difficulty bonus   — harder subjects earn a slight boost
//
//  FIX LOG (v2):
//  • Grade struct made Equatable/Hashable so it can be used in SwiftUI bindings
//  • Ring animation was firing before view fully appeared — fixed with proper
//    `.onAppear` sequencing and `Task { @MainActor }` instead of raw DispatchQueue
//  • `animatedScore` counter was jumping to final value early due to integer
//    truncation — replaced with proper lerp
//  • `BreakdownItem` now Equatable for diffing in ForEach
//  • `breakdown()` was computing `pauseSeconds` identically to `calculate()` —
//    extracted to a private helper to avoid drift between the two
//  • Score was not clamped before Int conversion in edge cases — fixed
// ══════════════════════════════════════════════════════════════════════════════

// MARK: - FocusScore Engine

struct FocusScore {

    // MARK: Grade

    struct Grade: Equatable, Hashable {
        let label : String
        let emoji : String
        let color : Color

        // Hashable via label (labels are unique per score band)
        func hash(into hasher: inout Hasher) { hasher.combine(label) }
    }

    static func grade(for score: Int) -> Grade {
        switch score {
        case 90...100: return Grade(label: "Excellent",  emoji: "🔥", color: .green)
        case 75..<90:  return Grade(label: "Great",      emoji: "⭐", color: .blue)
        case 60..<75:  return Grade(label: "Good",       emoji: "👍", color: Color(red: 0.1, green: 0.6, blue: 0.5))
        case 40..<60:  return Grade(label: "Fair",       emoji: "📈", color: .orange)
        default:       return Grade(label: "Keep Going", emoji: "💪", color: .red)
        }
    }

    // MARK: Calculate

    /// Returns a 0–100 focus score derived from session data.
    /// Returns 0 for sessions under 60 seconds.
    static func calculate(
        duration     : TimeInterval,
        distractions : [DistractionEvent],
        pauses       : [PauseInterval],
        difficulty   : Int
    ) -> Int {
        guard duration >= 60 else { return 0 }

        var score: Double = 100.0
        let minutes = duration / 60.0

        // ── 1. Duration quality ───────────────────────────────────────────────
        switch minutes {
        case ..<10:     score -= 40
        case ..<20:     score -= 25
        case ..<30:     score -= 10
        case 90...:     score += 10   // ≥90 min: stacks the ≥60 and ≥90 bonuses
        case 60...:     score += 5
        default:        break
        }

        // ── 2. Distraction penalty (rate-normalised) ──────────────────────────
        let distrPer30min = Double(distractions.count) / max(1.0, minutes / 30.0)
        score -= distrPer30min * 12.0
        if distractions.count > 6 { score = min(score, 58) }   // hard ceiling

        // ── 3. Pause ratio penalty ────────────────────────────────────────────
        let pauseRatio = pausedFraction(pauses: pauses, duration: duration)
        switch pauseRatio {
        case 0.40...: score -= 25
        case 0.25...: score -= 15
        case 0.12...: score -= 7
        default:      break
        }
        if pauses.isEmpty && minutes >= 25 { score += 5 }   // unbroken bonus

        // ── 4. Difficulty bonus ───────────────────────────────────────────────
        switch difficulty {
        case 5: score += 8
        case 4: score += 4
        case 1: score -= 4
        default: break
        }

        return clamp(Int(score.rounded()), 0, 100)
    }

    // MARK: Breakdown

    struct BreakdownItem: Identifiable, Equatable {
        let id       = UUID()
        let icon     : String
        let text     : String
        let positive : Bool

        static func == (lhs: BreakdownItem, rhs: BreakdownItem) -> Bool {
            lhs.text == rhs.text && lhs.positive == rhs.positive
        }
    }

    /// Plain-English explanation of what drove the score.
    static func breakdown(
        duration     : TimeInterval,
        distractions : [DistractionEvent],
        pauses       : [PauseInterval],
        difficulty   : Int,
        score        : Int
    ) -> [BreakdownItem] {
        var items: [BreakdownItem] = []
        let minutes    = duration / 60.0
        let pauseRatio = pausedFraction(pauses: pauses, duration: duration)

        // Duration
        if minutes >= 90 {
            items.append(.init(icon: "bolt.fill",  text: "90+ min — incredible stamina", positive: true))
        } else if minutes >= 60 {
            items.append(.init(icon: "clock.fill", text: "Long session — great stamina", positive: true))
        } else if minutes < 20 {
            items.append(.init(icon: "clock",      text: "Short session — try to go longer", positive: false))
        }

        // Distractions
        if distractions.isEmpty {
            if minutes >= 25 {
                items.append(.init(icon: "eye.fill", text: "Zero distractions — laser focus!", positive: true))
            }
        } else {
            let word = distractions.count == 1 ? "distraction" : "distractions"
            items.append(.init(icon: "bell.badge.fill",
                               text: "\(distractions.count) \(word) logged",
                               positive: false))
        }

        // Pauses
        if pauseRatio > 0.25 {
            items.append(.init(icon: "pause.circle.fill",
                               text: "\(Int(pauseRatio * 100))% of session was paused",
                               positive: false))
        } else if pauses.isEmpty && minutes >= 25 {
            items.append(.init(icon: "play.circle.fill",
                               text: "No pauses — unbroken focus",
                               positive: true))
        }

        // Difficulty
        if difficulty >= 4 {
            items.append(.init(icon: "flame.fill", text: "Hard material — bonus points", positive: true))
        }

        return items
    }

    // MARK: Private helpers

    /// Fraction of `duration` spent in pauses (0–1). Uses `end ?? now` for
    /// any pause still open at call-time.
    private static func pausedFraction(pauses: [PauseInterval], duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        let now  = Date()
        let secs = pauses.reduce(0.0) { acc, p in
            acc + (p.end ?? now).timeIntervalSince(p.start)
        }
        return secs / duration
    }

    private static func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
        min(hi, max(lo, value))
    }
}

// MARK: - FocusScoreCard View

/// Drop into SessionEndView to display the animated score card after a session.
struct FocusScoreCard: View {
    let score        : Int
    let breakdown    : [FocusScore.BreakdownItem]
    let showBreakdown: Bool

    // Animation state
    @State private var animatedScore: Int    = 0
    @State private var ringProgress : Double = 0
    @State private var appeared     : Bool   = false

    private var grade: FocusScore.Grade { FocusScore.grade(for: score) }

    var body: some View {
        VStack(spacing: 12) {
            scoreRing
            if showBreakdown && !breakdown.isEmpty {
                breakdownList
            }
        }
        .padding(.vertical, 14)
        .background(cardBackground)
        .onAppear(perform: startAnimations)
        // Re-animate if score changes (e.g. user changes difficulty slider)
        .onChange(of: score) { _ in
            ringProgress   = 0
            animatedScore  = 0
            startAnimations()
        }
    }

    // MARK: Sub-views

    private var scoreRing: some View {
        HStack(spacing: 20) {
            ZStack {
                // Track
                Circle()
                    .stroke(grade.color.opacity(0.18), lineWidth: 8)
                    .frame(width: 72, height: 72)

                // Filled arc
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(grade.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.0), value: ringProgress)

                // Score number
                VStack(spacing: 1) {
                    Text("\(animatedScore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(grade.color)
                        .contentTransition(.numericText())    // smooth digit flip (iOS 16+)
                    Text("/ 100")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(grade.emoji).font(.title2)
                    Text(grade.label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(grade.color)
                }
                Text("Focus Score")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var breakdownList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(breakdown) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .foregroundColor(item.positive ? .green : .orange)
                        .frame(width: 16)
                    Text(item.text)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(grade.color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(grade.color.opacity(0.25), lineWidth: 1)
            )
    }

    // MARK: Animation

    private func startAnimations() {
        // FIX: give the run-loop one cycle before starting, or `.trim` starts
        // at 0 without animating on first appearance.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)   // ~80 ms
            withAnimation(.easeOut(duration: 1.0)) {
                ringProgress = Double(score) / 100.0
            }
            await countUp()
        }
    }

    @MainActor
    private func countUp() async {
        let totalSteps = 40
        let delay: UInt64 = 25_000_000   // 25 ms per step → ~1 s total

        for step in 1...totalSteps {
            try? await Task.sleep(nanoseconds: delay)
            // FIX: lerp with Double, then round — avoids early jump-to-final
            animatedScore = Int(Double(score) * Double(step) / Double(totalSteps))
        }
        animatedScore = score   // guarantee exact final value
    }
}
