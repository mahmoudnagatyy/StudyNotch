import AppKit
import Combine

// ── Stage Manager Detector ────────────────────────────────────────────────────
//
//  Detects whether Stage Manager is currently active on macOS 13+.
//  Stage Manager reserves ~105pt on the left side of the screen for the
//  app tile strip. The notch pill is centre-aligned so it's naturally safe,
//  but other windows (Analytics, Study Plan) should be aware of this margin.
//
//  Also serves as the hook for Dynamic Island / Live Activity support
//  when Apple adds that hardware to MacBooks (expected ~2026).

@Observable
final class StageManagerDetector {
    static let shared = StageManagerDetector()

     var isActive: Bool = false

    // Width of the Stage Manager tile strip (left inset) — 0 when inactive
     var leftInset: CGFloat = 0

    // Whether the display has a physical notch (hardware camera housing)
     var hasNotch: Bool = false

    // Dynamic Island: will be true when Apple ships DI on MacBooks
    // Currently always false — placeholder for future detection
     var hasDynamicIsland: Bool = false

    private var timer: Timer?

    init() {
        refresh()
        // Poll every 2 seconds to catch Stage Manager toggle without app restart
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Also react to screen parameter changes (display connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc func refresh() {
        guard let screen = NSScreen.main else { return }

        // ── Notch detection ───────────────────────────────────────────────────
        if #available(macOS 12.0, *) {
            let newHasNotch = screen.safeAreaInsets.top > NSStatusBar.system.thickness
            if newHasNotch != hasNotch { hasNotch = newHasNotch }
        }

        // ── Stage Manager detection ───────────────────────────────────────────
        //
        //  When Stage Manager is on, `NSScreen.main.visibleFrame.minX` is
        //  pushed right by ~105pt (the tile strip width). We compare
        //  visibleFrame.minX to screen.frame.minX to detect this offset.
        //
        //  Note: this also accounts for the Dock being on the left side.
        //  We distinguish Stage Manager by checking macOS 13+ default tile width.

        let visible = screen.visibleFrame
        let full    = screen.frame

        // The Stage Manager strip is ~105pt wide — use 90pt threshold to distinguish from Dock
        let leftDiff = visible.minX - full.minX
        let newIsActive: Bool
        let newLeftInset: CGFloat

        if #available(macOS 13.0, *) {
            // On macOS 13+, Stage Manager inset is ~105pt
            // The Dock on left is usually 60-80pt — we use >90pt as threshold
            let likelyStageManager = leftDiff > 90 && leftDiff < 140
            newIsActive  = likelyStageManager
            newLeftInset = likelyStageManager ? leftDiff : 0
        } else {
            newIsActive  = false
            newLeftInset = 0
        }

        DispatchQueue.main.async {
            if newIsActive != self.isActive   { self.isActive  = newIsActive }
            if newLeftInset != self.leftInset { self.leftInset = newLeftInset }
        }
    }

    // ── Convenience ───────────────────────────────────────────────────────────

    /// Safe window origin X — accounts for Stage Manager strip
    var safeOriginX: CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        return isActive ? screen.frame.minX + leftInset : screen.frame.minX
    }

    /// Recommended window placement — centres a window in the Stage Manager
    /// working area (excluding the tile strip on the left)
    func centredRect(width: CGFloat, height: CGFloat) -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 100, y: 100, width: width, height: height)
        }
        let workArea = screen.visibleFrame
        let x = workArea.midX - width / 2
        let y = workArea.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // ── Dynamic Island hook ───────────────────────────────────────────────────
    //
    //  When Apple ships Dynamic Island on MacBooks, this method will be
    //  called to present a Live Activity in the island during active sessions.
    //  For now it falls back to the existing notch pill behaviour.

    func presentLiveActivity(subject: String, elapsed: TimeInterval) {
        // Future: ActivityKit / Live Activities API
        // guard hasDynamicIsland else { return }
        // Currently: no-op — notch pill handles this
    }

    func endLiveActivity() {
        // Future: ActivityKit dismiss
    }
}
