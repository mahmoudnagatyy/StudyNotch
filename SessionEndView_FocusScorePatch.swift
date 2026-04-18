// ══════════════════════════════════════════════════════════════════════════════
//  SessionEndView_FocusScorePatch.swift
//  StudyNotch — Integration Guide
//
//  Copy the marked snippets into SessionEndView.swift.
//  This file itself does NOT need to be added to your Xcode target.
// ══════════════════════════════════════════════════════════════════════════════

/*
 ─────────────────────────────────────────────────────────────────────────────
 STEP 1 — Add computed properties just before `var body: some View`
 ─────────────────────────────────────────────────────────────────────────────

     /// Score recalculated live whenever the user adjusts the difficulty slider
     var liveScore: Int {
         guard let sd = sessionData else { return 0 }
         return FocusScore.calculate(
             duration    : sd.duration,
             distractions: sd.distractions,
             pauses      : sd.pauses,
             difficulty  : difficulty
         )
     }

     var liveBreakdown: [FocusScore.BreakdownItem] {
         guard let sd = sessionData else { return [] }
         return FocusScore.breakdown(
             duration    : sd.duration,
             distractions: sd.distractions,
             pauses      : sd.pauses,
             difficulty  : difficulty,
             score       : liveScore
         )
     }

 ─────────────────────────────────────────────────────────────────────────────
 STEP 2 — Insert FocusScoreCard into the ScrollView body,
           right after the header, before the subject/notes fields.
 ─────────────────────────────────────────────────────────────────────────────

     // Only show for real (timed) sessions, not manual entries
     if !isManualEntry {
         FocusScoreCard(
             score        : liveScore,
             breakdown    : liveBreakdown,
             showBreakdown: true
         )
         .padding(.horizontal, 20)
         .padding(.top, 12)
         // Card re-animates when the user changes the difficulty slider
         .animation(.easeOut(duration: 0.4), value: difficulty)
     }

 ─────────────────────────────────────────────────────────────────────────────
 STEP 3 — Score badge in history / analytics rows  (AnalyticsView or similar)
 ─────────────────────────────────────────────────────────────────────────────

     // Somewhere in your session row view alongside duration / subject:

     let grade = session.focusGrade
     HStack(spacing: 3) {
         Text(grade.emoji)
             .font(.caption2)
         Text("\(session.focusScore)")
             .font(.system(size: 11, weight: .semibold))
             .foregroundColor(grade.color)
     }
     .padding(.horizontal, 5)
     .padding(.vertical, 2)
     .background(grade.color.opacity(0.12))
     .clipShape(RoundedRectangle(cornerRadius: 4))

 ─────────────────────────────────────────────────────────────────────────────
 STEP 4 (NEW) — Weekly average score in a summary card
 ─────────────────────────────────────────────────────────────────────────────

     // In a weekly stats view, compute the average focus score:

     var weeklyAvgScore: Int {
         let scores = weekSessions.map(\.focusScore)
         guard !scores.isEmpty else { return 0 }
         return scores.reduce(0, +) / scores.count
     }

     // Then display a compact variant of FocusScoreCard:
     FocusScoreCard(
         score        : weeklyAvgScore,
         breakdown    : [],
         showBreakdown: false
     )

 ─────────────────────────────────────────────────────────────────────────────
 NOTE: No JSON migration needed.
       focusScore is computed from existing Codable fields at runtime,
       so historical sessions are scored automatically.
 ─────────────────────────────────────────────────────────────────────────────
*/

import SwiftUI

// MARK: - Xcode Previews

struct FocusScoreCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Excellent — long, no distractions, hard subject
            FocusScoreCard(
                score: 94,
                breakdown: FocusScore.breakdown(
                    duration    : 5_400,
                    distractions: [],
                    pauses      : [],
                    difficulty  : 5,
                    score       : 94
                ),
                showBreakdown: true
            )

            // Fair — short, distracted
            FocusScoreCard(
                score: 42,
                breakdown: FocusScore.breakdown(
                    duration    : 900,
                    distractions: [
                        DistractionEvent(timestamp: Date(), label: "Phone", offsetSec: 120),
                        DistractionEvent(timestamp: Date(), label: "Social media", offsetSec: 400),
                    ],
                    pauses      : [],
                    difficulty  : 2,
                    score       : 42
                ),
                showBreakdown: true
            )

            // Score-only badge (analytics row)
            FocusScoreCard(score: 78, breakdown: [], showBreakdown: false)
        }
        .padding()
        .frame(width: 360)
    }
}
