import SwiftUI

// ── Animated Ring ─────────────────────────────────────────────────────────────

struct GoalRing: View {
    let progress  : Double          // 0.0 → 1.0
    let color     : Color
    let size      : CGFloat
    let lineWidth : CGFloat

    @State private var animatedProgress: Double = 0

    // Always show at least a tiny nub so the ring is visible at 0%
    var displayProgress: Double { max(animatedProgress, 0.04) }

    var body: some View {
        ZStack {
            // Track — brighter so it's visible even when progress = 0
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)

            // Fill arc — min nub so ring always visible
            Circle()
                .trim(from: 0, to: displayProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Percentage label (only for larger rings)
            if size > 28 {
                VStack(spacing: 1) {
                    Text("\(Int(min(progress, 1.0) * 100))%")
                        .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                    if progress >= 1.0 {
                        Text("✓")
                            .font(.system(size: size * 0.18, weight: .bold))
                            .foregroundColor(color)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                animatedProgress = min(progress, 1.0)
            }
        }
        .onChange(of: progress) { newVal in
            withAnimation(.easeOut(duration: 0.6)) {
                animatedProgress = min(newVal, 1.0)
            }
        }
    }
}

// ── Stacked Multi-Subject Rings ───────────────────────────────────────────────

struct MultiGoalRing: View {
    var store    = SubjectStore.shared
    @Bindable var sessions = SessionStore.shared
    let subjects  : [String]
    let outerSize : CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(subjects.prefix(4).enumerated()), id: \.offset) { idx, sub in
                let progress = store.progress(for: sub, sessions: sessions.sessions)
                let sz       = outerSize - CGFloat(idx) * (outerSize / CGFloat(subjects.count + 1))
                let lw       = max(3.0, (outerSize / 10.0) - CGFloat(idx) * 0.8)
                GoalRing(progress: progress,
                         color: store.color(for: sub),
                         size: sz,
                         lineWidth: lw)
            }
        }
        .frame(width: outerSize, height: outerSize)
    }
}

// ── Compact ring for notch pill ───────────────────────────────────────────────

struct NotchGoalRing: View {
    var store    = SubjectStore.shared
    @Bindable var sessions = SessionStore.shared
    var timer    = StudyTimer.shared

    // Computed outside body to avoid let-in-ViewBuilder issues
    var globalProgress : Double { store.globalProgress(sessions: sessions.sessions) }
    var subjectProgress: Double { store.progress(for: timer.currentSubject, sessions: sessions.sessions) }
    var subjectColor   : Color  {
        timer.currentSubject.isEmpty
            ? Color(red: 0.2, green: 1.0, blue: 0.5)
            : store.color(for: timer.currentSubject)
    }
    var globalColor: Color { Color(red: 0.2, green: 1.0, blue: 0.5) }

    var body: some View {
        Group {
            if store.dailyGoalMode == .global {
                GoalRing(progress: globalProgress, color: globalColor, size: 18, lineWidth: 2.5)
            } else if store.dailyGoalMode == .perSubject {
                GoalRing(progress: subjectProgress, color: subjectColor, size: 18, lineWidth: 2.5)
            } else {
                // .both — two concentric rings
                ZStack {
                    GoalRing(progress: globalProgress,  color: globalColor,  size: 18, lineWidth: 2.0)
                    GoalRing(progress: subjectProgress, color: subjectColor, size: 11, lineWidth: 2.0)
                }
                .frame(width: 18, height: 18)
            }
        }
    }
}
