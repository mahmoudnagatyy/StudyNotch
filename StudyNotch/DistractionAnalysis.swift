import Foundation
import SwiftUI

// ── Distraction Pattern Analysis ─────────────────────────────────────────────
//
//  Analyses DistractionEvent data across all sessions to find:
//    - Peak distraction hours (when during the day)
//    - Peak distraction session offset (when during a session)
//    - Most common distraction labels (Phone, Social, etc.)
//    - Subjects with most distractions
//    - Average distractions per session (trending)

struct DistractionAnalysis {

    struct HourBucket: Identifiable {
        let id    = UUID()
        let hour  : Int      // 0–23
        let count : Int
        var label : String { String(format: "%02d:00", hour) }
    }

    struct OffsetBucket: Identifiable {
        let id       = UUID()
        let minuteIn : Int   // minute into session (0, 5, 10, …)
        let count    : Int
        var label    : String { "\(minuteIn)m" }
    }

    struct LabelCount: Identifiable {
        let id    = UUID()
        let label : String
        let count : Int
        let pct   : Double
    }

    struct SubjectCount: Identifiable {
        let id      = UUID()
        let subject : String
        let count   : Int
        let perSession: Double
    }

    // ── Computed results ──────────────────────────────────────────────────────

    let totalDistractions : Int
    let avgPerSession     : Double
    let peakHour          : Int?          // hour of day with most distractions
    let peakOffset        : Int?          // minute into session with most distractions
    let byHour            : [HourBucket]
    let byOffset          : [OffsetBucket]
    let byLabel           : [LabelCount]
    let bySubject         : [SubjectCount]
    let trend             : Double        // +ve = getting worse, -ve = improving
    let insightText       : String        // plain-English summary

    // ── Factory ───────────────────────────────────────────────────────────────

    static func analyse(sessions: [StudySession]) -> DistractionAnalysis {
        let allDistrs = sessions.flatMap { s in
            s.distractions.map { d in (session: s, event: d) }
        }

        let total    = allDistrs.count
        let avgPer   = sessions.isEmpty ? 0.0
            : Double(total) / Double(sessions.count)

        // By hour of day
        var hourMap  = [Int: Int]()
        for (_, d) in allDistrs {
            let hour = Calendar.current.component(.hour, from: d.timestamp)
            hourMap[hour, default: 0] += 1
        }
        let byHour = (0..<24).map { HourBucket(hour: $0, count: hourMap[$0] ?? 0) }
        let peakHour = hourMap.max(by: { $0.value < $1.value })?.key

        // By offset (5-min buckets within session)
        var offsetMap = [Int: Int]()
        for (_, d) in allDistrs {
            let bucket = (d.offsetSec / 300) * 5  // round to nearest 5 min
            offsetMap[bucket, default: 0] += 1
        }
        let maxOffset = (offsetMap.keys.max() ?? 0) + 5
        let byOffset = stride(from: 0, to: maxOffset + 1, by: 5).map {
            OffsetBucket(minuteIn: $0, count: offsetMap[$0] ?? 0)
        }
        let peakOffset = offsetMap.max(by: { $0.value < $1.value })?.key

        // By label
        var labelMap = [String: Int]()
        for (_, d) in allDistrs { labelMap[d.label, default: 0] += 1 }
        let labelTotal = max(1, labelMap.values.reduce(0, +))
        let byLabel = labelMap.sorted { $0.value > $1.value }.map {
            LabelCount(label: $0.key, count: $0.value,
                       pct: Double($0.value) / Double(labelTotal))
        }

        // By subject
        var subMap = [String: (count: Int, sessions: Int)]()
        for s in sessions {
            let prev = subMap[s.subject] ?? (0, 0)
            subMap[s.subject] = (prev.count + s.distractions.count, prev.sessions + 1)
        }
        let bySubject = subMap.map {
            SubjectCount(subject: $0.key, count: $0.value.count,
                         perSession: $0.value.sessions > 0
                            ? Double($0.value.count) / Double($0.value.sessions) : 0)
        }.sorted { $0.perSession > $1.perSession }

        // Trend: compare first half vs second half of sessions (chronological)
        let sorted  = sessions.sorted { $0.startTime < $1.startTime }
        let half    = max(1, sorted.count / 2)
        let first   = sorted.prefix(half).map { Double($0.distractions.count) }.reduce(0, +) / Double(half)
        let second  = sorted.suffix(half).map { Double($0.distractions.count) }.reduce(0, +) / Double(half)
        let trend   = second - first  // positive = more distractions recently

        // Insight text
        var insights: [String] = []
        if let ph = peakHour {
            let nextH = (ph + 1) % 24
            insights.append("You're most distracted between \(String(format:"%02d:00",ph))–\(String(format:"%02d:00",nextH)).")
        }
        if let po = peakOffset {
            insights.append("Distractions peak around \(po)–\(po+5) minutes into a session — consider a quick reset at that point.")
        }
        if let top = byLabel.first, top.count > 1 {
            insights.append("\(top.label) is your most common distraction (\(Int(top.pct*100))% of all).")
        }
        if trend > 0.5 {
            insights.append("⚠️ Your distractions are increasing. Try shorter sessions or environment changes.")
        } else if trend < -0.3 {
            insights.append("✅ You're improving — fewer distractions in recent sessions.")
        }
        if let worst = bySubject.first, worst.perSession > 1 {
            insights.append("\(worst.subject) has the most distractions per session (avg \(String(format:"%.1f",worst.perSession))).")
        }

        let insightText = insights.joined(separator: " ")

        return DistractionAnalysis(
            totalDistractions: total,
            avgPerSession: avgPer,
            peakHour: peakHour,
            peakOffset: peakOffset,
            byHour: byHour,
            byOffset: Array(byOffset),
            byLabel: byLabel,
            bySubject: bySubject,
            trend: trend,
            insightText: insightText.isEmpty ? "No distraction data yet. Start logging sessions to see patterns." : insightText
        )
    }
}

// ── Distraction Analytics View ────────────────────────────────────────────────

struct DistractionAnalyticsView: View {
    @Bindable var store = SessionStore.shared
    @State private var animateIn      = false
    @State private var selectedHour   : Int?    = nil  // tapped bar in hour chart
    @State private var selectedOffset : Int?    = nil  // tapped bar in offset chart
    @State private var selectedLabel  : String? = nil  // tapped label row
    @State private var selectedSubject: String? = nil  // tapped subject row

    var analysis: DistractionAnalysis {
        DistractionAnalysis.analyse(sessions: store.sessions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Insight banner ────────────────────────────────────────────
                if !analysis.insightText.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16)).foregroundColor(.purple)
                            .scaleEffect(animateIn ? 1 : 0.3)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: animateIn)
                        Text(analysis.insightText)
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.2), lineWidth: 0.5))
                    .offset(y: animateIn ? 0 : 20).opacity(animateIn ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.05), value: animateIn)
                }

                // ── Overview stats ────────────────────────────────────────────
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible())], spacing: 10) {
                    distrStat("Total", "\(analysis.totalDistractions)", "bolt.slash.fill", .red,   delay: 0.10)
                    distrStat("Per Session", String(format: "%.1f", analysis.avgPerSession), "chart.bar", .orange, delay: 0.15)
                    distrStat("Trend", analysis.trend > 0.3 ? "↑ Worse" : analysis.trend < -0.3 ? "↓ Better" : "Stable",
                              analysis.trend > 0 ? "arrow.up.right" : "arrow.down.right",
                              analysis.trend > 0.3 ? .red : analysis.trend < -0.3 ? .green : .secondary,
                              delay: 0.20)
                }

                // ── Charts ────────────────────────────────────────────────────
                if analysis.totalDistractions > 0 {
                    hourChart
                        .offset(y: animateIn ? 0 : 20).opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.25), value: animateIn)
                    offsetChart
                        .offset(y: animateIn ? 0 : 20).opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.35), value: animateIn)
                    labelBreakdown
                        .offset(y: animateIn ? 0 : 20).opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.45), value: animateIn)
                    subjectBreakdown
                        .offset(y: animateIn ? 0 : 20).opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.55), value: animateIn)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.slash").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.3))
                        Text("No distractions logged yet").font(.system(size: 13)).foregroundColor(.secondary)
                        Text("When you log distractions during sessions, patterns will appear here.")
                            .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .onAppear {
            animateIn = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation { animateIn = true }
            }
        }
    }

    var hourChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").foregroundColor(.orange)
                Text("Distractions by Time of Day").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let h = selectedHour {
                    let cnt = analysis.byHour.first { $0.hour == h }?.count ?? 0
                    Text("\(String(format: "%02d:00", h)) — \(cnt) distraction\(cnt == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.orange)
                        .transition(.opacity)
                }
            }
            let maxCount = max(1, analysis.byHour.map { $0.count }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(analysis.byHour.filter { $0.hour >= 6 && $0.hour <= 23 }) { bucket in
                    let isPeak    = bucket.hour == analysis.peakHour
                    let isSelected = bucket.hour == selectedHour
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? Color.white : isPeak ? Color.red : Color.orange.opacity(0.5))
                            .frame(height: animateIn ? CGFloat(bucket.count) / CGFloat(maxCount) * 50 + 2 : 2)
                            .shadow(color: isSelected ? .white.opacity(0.6) : .clear, radius: 4)
                        if bucket.hour % 4 == 0 {
                            Text("\(bucket.hour)").font(.system(size: 7))
                                .foregroundColor(isSelected ? .orange : .secondary)
                        } else {
                            Text(" ").font(.system(size: 7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isSelected ? 1.1 : 1.0, anchor: .bottom)
                    .animation(.easeOut(duration: 0.6).delay(Double(bucket.hour) * 0.02), value: animateIn)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedHour)
                    .onTapGesture {
                        withAnimation { selectedHour = selectedHour == bucket.hour ? nil : bucket.hour }
                    }
                    .contentShape(Rectangle())
                }
            }
            .frame(height: 62)
            if selectedHour == nil, let ph = analysis.peakHour {
                Text("Tap a bar for details · Peak: \(String(format: "%02d:00", ph))–\(String(format: "%02d:00", (ph+1)%24))")
                    .font(.system(size: 10)).foregroundColor(.orange.opacity(0.7))
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.1), lineWidth: 0.5))
    }

    var offsetChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "timer").foregroundColor(.yellow)
                Text("When in a Session").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let o = selectedOffset {
                    let cnt = analysis.byOffset.first { $0.minuteIn == o }?.count ?? 0
                    Text("\(o)–\(o+5) min — \(cnt) distraction\(cnt == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.yellow)
                        .transition(.opacity)
                }
            }
            let visible = analysis.byOffset.filter { $0.minuteIn <= 60 }
            let maxC    = max(1, visible.map { $0.count }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(visible) { bucket in
                    let isPeak     = bucket.minuteIn == analysis.peakOffset
                    let isSelected = bucket.minuteIn == selectedOffset
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? Color.white : isPeak ? Color.red : Color.yellow.opacity(0.6))
                            .frame(height: animateIn ? CGFloat(bucket.count) / CGFloat(maxC) * 44 + 2 : 2)
                            .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 3)
                        if bucket.minuteIn % 15 == 0 {
                            Text("\(bucket.minuteIn)m").font(.system(size: 7))
                                .foregroundColor(isSelected ? .yellow : .secondary)
                        } else {
                            Text(" ").font(.system(size: 7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isSelected ? 1.1 : 1.0, anchor: .bottom)
                    .animation(.easeOut(duration: 0.5).delay(Double(bucket.minuteIn) * 0.01), value: animateIn)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectedOffset)
                    .onTapGesture {
                        withAnimation { selectedOffset = selectedOffset == bucket.minuteIn ? nil : bucket.minuteIn }
                    }
                    .contentShape(Rectangle())
                }
            }
            .frame(height: 56)
            if selectedOffset == nil, let po = analysis.peakOffset {
                Text("Tap a bar for details · Peak: \(po)–\(po+5) min mark")
                    .font(.system(size: 10)).foregroundColor(.yellow.opacity(0.7))
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.1), lineWidth: 0.5))
    }

    var labelBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill").foregroundColor(.blue)
                Text("Distraction Types").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let lbl = selectedLabel,
                   let item = analysis.byLabel.first(where: { $0.label == lbl }) {
                    Text("\(item.count) times (\(Int(item.pct * 100))%)")
                        .font(.system(size: 10)).foregroundColor(.blue)
                }
            }
            ForEach(analysis.byLabel.prefix(5)) { item in
                labelRow(item)
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.1), lineWidth: 0.5))
    }

    // Extracted to avoid "compiler unable to type-check" on complex closures
    func labelRow(_ item: DistractionAnalysis.LabelCount) -> some View {
        let isSelected = item.label == selectedLabel
        return HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .blue : .white.opacity(0.8))
                .frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.white : Color.blue.opacity(0.7))
                        .frame(width: animateIn ? geo.size.width * CGFloat(item.pct) : 0, height: 8)
                        .animation(.easeOut(duration: 0.6), value: animateIn)
                        .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 3)
                }
            }
            .frame(height: 8)
            Text("\(Int(item.pct * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            withAnimation(.spring(response: 0.25)) {
                selectedLabel = selectedLabel == item.label ? nil : item.label
            }
        }
        .animation(.spring(response: 0.25), value: selectedLabel)
    }

    var subjectBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill").foregroundColor(.purple)
                Text("By Subject (avg per session)").font(.system(size: 13, weight: .semibold))
                Spacer()
                if selectedSubject != nil {
                    Button("✕") { withAnimation { selectedSubject = nil } }
                        .buttonStyle(.plain).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            ForEach(analysis.bySubject.prefix(5)) { item in
                let isSelected = item.subject == selectedSubject
                let color = SubjectStore.shared.color(for: item.subject)
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(item.subject)
                        .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? color : .white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSelected {
                        Text("\(item.count) total · \(String(format:"%.1f",item.perSession))/session")
                            .font(.system(size: 10)).foregroundColor(color)
                            .transition(.opacity)
                    } else {
                        Text(String(format: "%.1f/session", item.perSession))
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                        Text("\(item.count)")
                            .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8)).foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.vertical, 5).padding(.horizontal, 6)
                .background(isSelected ? color.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(isSelected ? RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 0.5) : nil)
                .onTapGesture {
                    withAnimation(.spring(response: 0.25)) {
                        selectedSubject = selectedSubject == item.subject ? nil : item.subject
                    }
                }
                .animation(.spring(response: 0.25), value: selectedSubject)
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.1), lineWidth: 0.5))
    }

    func distrStat(_ title: String, _ value: String, _ icon: String, _ color: Color, delay: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
            Text(title).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.1), lineWidth: 0.5))
        .offset(y: animateIn ? 0 : 14).opacity(animateIn ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(delay), value: animateIn)
    }
}
