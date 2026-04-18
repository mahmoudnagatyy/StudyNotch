import SwiftUI
import AppKit

// ── Session Replay ────────────────────────────────────────────────────────────
// Shows a visual timeline of a session: focus blocks, pauses, distractions.

struct SessionReplayView: View {
    let session: StudySession
    @Environment(\.dismiss) var dismiss

    var totalDuration: TimeInterval { max(session.duration, 1) }

    @State private var playheadPct  : Double = 0
    @State private var isReplaying  : Bool   = false
    @State private var replayTimer  : Timer? = nil
    @State private var replaySpeed  : Double = 10
    @State private var showEditSheet : Bool   = false
    @State private var editSession   : StudySession? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.subject)
                        .font(.system(size: 18, weight: .bold))
                    Text(sessionDateString)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // ── Stat pills ─────────────────────────────────────────────
                    HStack(spacing: 10) {
                        statPill("clock",         fmtDur(session.duration),          .blue)
                        statPill("pause.circle",  "\(session.pauses.count) pauses",  .orange)
                        statPill("bolt.slash",    "\(session.distractions.count) distractions", .red)
                        if session.difficulty > 0 {
                            statPill("star.fill", "Diff \(session.difficulty)/5",    diffColor(session.difficulty))
                        }
                    }

                    // ── Replay controls ────────────────────────────────────────
                    HStack(spacing: 10) {
                        Button { isReplaying ? stopReplay() : startReplay() } label: {
                            Label(isReplaying ? "Pause" : "▶ Replay",
                                  systemImage: isReplaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(isReplaying ? Color.orange : Color.green)
                        .clipShape(Capsule())

                        Button { playheadPct = 0 } label: {
                            Image(systemName: "backward.end.fill").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundColor(.secondary)

                        Picker("", selection: $replaySpeed) {
                            Text("5×").tag(5.0)
                            Text("10×").tag(10.0)
                            Text("30×").tag(30.0)
                        }
                        .pickerStyle(.segmented).frame(width: 120)

                        Spacer()
                        Text(fmtOffset(Int(playheadPct * totalDuration)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    // ── Visual Timeline ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Timeline")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.12))
                                    .frame(height: 28)

                                // Focus blocks (green)
                                ForEach(focusBlocks, id: \.start) { block in
                                    let x = geo.size.width * CGFloat(block.start / totalDuration)
                                    let w = geo.size.width * CGFloat(block.duration / totalDuration)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green.opacity(0.75))
                                        .frame(width: max(w, 2), height: 28)
                                        .offset(x: x)
                                }

                                // Pause blocks (orange)
                                ForEach(session.pauses, id: \.start) { pause in
                                    let offset = pause.start.timeIntervalSince(session.startTime)
                                    let dur    = pause.duration
                                    let x = geo.size.width * CGFloat(offset / totalDuration)
                                    let w = geo.size.width * CGFloat(dur / totalDuration)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: max(w, 3), height: 28)
                                        .offset(x: x)
                                }

                                // Distraction markers (red triangles)
                                ForEach(session.distractions) { d in
                                    let x = geo.size.width * CGFloat(Double(d.offsetSec) / totalDuration)
                                    VStack(spacing: 0) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.red)
                                        Rectangle().fill(Color.red).frame(width: 2, height: 28)
                                    }
                                    .offset(x: x - 1)
                                }
                            }
                        }
                        .frame(height: 28)

                        // Playhead — animated white scrubber line
                        GeometryReader { g in
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 2, height: 34)
                                .offset(x: max(0, min(g.size.width - 2,
                                               g.size.width * CGFloat(playheadPct) - 1)))
                                .shadow(color: .white.opacity(0.8), radius: 4)
                                .animation(.linear(duration: 0.05), value: playheadPct)
                        }
                        .frame(height: 34)
                        .offset(y: -5)

                        // Legend
                        HStack(spacing: 16) {
                            legendItem(.green.opacity(0.75),   "Focus")
                            legendItem(.orange.opacity(0.7),   "Pause")
                            legendItem(.red,                   "Distraction")
                        }
                        .font(.system(size: 10))

                        // Time labels
                        HStack {
                            Text(timeFmt.string(from: session.startTime))
                            Spacer()
                            Text(timeFmt.string(from: session.endTime))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    }

                    // ── Pauses ─────────────────────────────────────────────────
                    if !session.pauses.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pauses (\(session.pauses.count))")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            ForEach(Array(session.pauses.enumerated()), id: \.offset) { idx, pause in
                                HStack {
                                    Text("#\(idx + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.orange)
                                        .frame(width: 24)
                                    Text("\(timeFmt.string(from: pause.start))")
                                        .font(.system(size: 11, design: .monospaced))
                                    if let end = pause.end {
                                        Text("→ \(timeFmt.string(from: end))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(fmtDur(pause.duration))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.orange.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // ── Distractions ───────────────────────────────────────────
                    if !session.distractions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Distractions (\(session.distractions.count))")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            ForEach(session.distractions) { d in
                                HStack(spacing: 10) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10)).foregroundColor(.red)
                                    Text(d.label).font(.system(size: 12))
                                    Spacer()
                                    Text("@\(fmtOffset(d.offsetSec))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(timeFmt.string(from: d.timestamp))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.red.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // ── App Usage ─────────────────────────────────────────────
                    if !session.appUsage.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("App Usage Breakdown")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            
                            let sorted = session.appUsage.sorted { $0.value > $1.value }
                            FlowLayout(spacing: 8) {
                                ForEach(Array(sorted), id: \.key) { bid, duration in
                                    appChip(appName(bid), duration)
                                }
                            }
                        }
                    }

                    // ── Notes ──────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("What was covered")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            Spacer()
                            Button {
                                editSession = session
                                showEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if session.notes.isEmpty {
                            Text("No notes — tap Edit to add some")
                                .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.5))
                                .italic()
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            style: StrokeStyle(lineWidth: 1, dash: [4]),
                                            antialiased: true
                                        )
                                        .foregroundColor(Color.white.opacity(0.08))
                                )
                        } else {
                            Text(session.notes)
                                .font(.system(size: 13))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .sheet(item: $editSession) { s in
                        SessionEditSheet(session: s)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 580)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Build focus block intervals (gaps between pauses)
    var focusBlocks: [(start: TimeInterval, duration: TimeInterval)] {
        var blocks: [(TimeInterval, TimeInterval)] = []
        var cursor: TimeInterval = 0
        for pause in session.pauses.sorted(by: { $0.start < $1.start }) {
            let pauseOffset = pause.start.timeIntervalSince(session.startTime)
            if pauseOffset > cursor {
                blocks.append((cursor, pauseOffset - cursor))
            }
            cursor = (pause.end ?? pause.start).timeIntervalSince(session.startTime)
        }
        if cursor < totalDuration {
            blocks.append((cursor, totalDuration - cursor))
        }
        return blocks
    }

    func startReplay() {
        stopReplay(); playheadPct = 0; isReplaying = true
        replayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            DispatchQueue.main.async {
                self.playheadPct += (0.05 * self.replaySpeed) / self.totalDuration
                if self.playheadPct >= 1.0 { self.playheadPct = 1.0; self.stopReplay() }
            }
        }
    }

    func stopReplay() {
        replayTimer?.invalidate(); replayTimer = nil; isReplaying = false
    }

    var sessionDateString: String {
        let f = DateFormatter()
        f.dateStyle = .full; f.timeStyle = .short
        return f.string(from: session.startTime)
    }

    var timeFmt: DateFormatter {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }

    func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60; let s = Int(d)%60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    func fmtOffset(_ sec: Int) -> String {
        let m = sec/60; let s = sec%60
        return String(format: "%d:%02d", m, s)
    }

    func statPill(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12)).clipShape(Capsule())
    }

    func appName(_ bid: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return path.lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }
        return bid.components(separatedBy: ".").last ?? bid
    }

    func appChip(_ name: String, _ duration: TimeInterval) -> some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 10, weight: .semibold))
            Text(fmtDur(duration)).font(.system(size: 9)).opacity(0.7)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }

    private func diffColor(_ d: Int) -> Color {
        if d >= 4 { return .red }
        if d >= 3 { return .orange }
        return .green
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────

class SessionReplayWindowController: NSWindowController {
    static var shared: SessionReplayWindowController?

    static func present(_ session: StudySession) {
        shared?.close()
        let c = SessionReplayWindowController(session: session)
        shared = c; c.showWindow(nil); c.window?.makeKeyAndOrderFront(nil)
    }

    init(session: StudySession) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "Session Replay — \(session.subject)"
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 420, height: 460)
        win.center()
        win.contentView = NSHostingView(rootView: SessionReplayView(session: session))
        super.init(window: win); win.delegate = self
    }
    required init?(coder: NSCoder) { nil }
}

extension SessionReplayWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SessionReplayWindowController.shared = nil
        DispatchQueue.main.async { NotchWindowController.shared?.window?.orderFrontRegardless() }
    }
}
