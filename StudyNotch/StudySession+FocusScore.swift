import Foundation

// ══════════════════════════════════════════════════════════════════════════════
//  StudySession+FocusScore.swift
//  StudyNotch
//
//  Extends StudySession with computed focus score properties.
//  No Codable migration required — the score is derived at runtime from
//  existing stored fields (duration, distractions, pauses, difficulty).
//  This means ALL past sessions get accurate scores automatically.
//
//  FIX LOG (v2):
//  • Added `focusBreakdown` convenience property so call-sites don't need
//    to duplicate the `FocusScore.breakdown(...)` call.
//  • Added `focusScoreCategory` for use in Charts (bucketed 0–4 Int).
// ══════════════════════════════════════════════════════════════════════════════

extension StudySession {

    /// 0–100 focus quality score computed from session data.
    var focusScore: Int {
        FocusScore.calculate(
            duration    : duration,
            distractions: distractions,
            pauses      : pauses,
            difficulty  : difficulty
        )
    }

    /// Grade label, emoji, and colour for the current score.
    var focusGrade: FocusScore.Grade {
        FocusScore.grade(for: focusScore)
    }

    /// Plain-English breakdown items explaining what drove the score.
    var focusBreakdown: [FocusScore.BreakdownItem] {
        FocusScore.breakdown(
            duration    : duration,
            distractions: distractions,
            pauses      : pauses,
            difficulty  : difficulty,
            score       : focusScore
        )
    }

    /// Bucketed category (0–4) useful for Charts / bar groupings.
    ///  0 = Keep Going (<40)
    ///  1 = Fair       (40–59)
    ///  2 = Good       (60–74)
    ///  3 = Great      (75–89)
    ///  4 = Excellent  (90–100)
    var focusScoreCategory: Int {
        switch focusScore {
        case 90...: return 4
        case 75...: return 3
        case 60...: return 2
        case 40...: return 1
        default:    return 0
        }
    }
}
