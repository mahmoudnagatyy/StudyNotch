import SwiftUI
import AppKit

// ── Share Card View ───────────────────────────────────────────────────────────
//
//  Renders a 1080×1080 (or 9:16 for TikTok) image card showing:
//    - Total study hours today / this week / streak
//    - Subject breakdown
//    - Exported as PNG via NSImage rendering

struct ShareCardView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var sessions = SessionStore.shared
    @Bindable var subStore = SubjectStore.shared
    @State private var selectedStyle  : CardStyle = .today
    @State private var selectedPalette: CardPalette = .dark
    @State private var exportedImage  : NSImage?    = nil
    @State private var isExporting    = false
    @State private var exportMessage  = ""

    enum CardStyle: String, CaseIterable {
        case today   = "Today"
        case week    = "This Week"
        case streak  = "Streak"
    }

    enum CardPalette: String, CaseIterable {
        case dark   = "Dark"
        case neon   = "Neon"
        case minimal = "Clean"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Share Study Card").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundColor(.accentColor)
            }
            .padding(16)

            Divider()

            HStack(spacing: 20) {
                // Card preview
                cardPreview
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

                // Controls
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Style").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        Picker("", selection: $selectedStyle) {
                            ForEach(CardStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        Picker("", selection: $selectedPalette) {
                            ForEach(CardPalette.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        Button {
                            exportCard()
                        } label: {
                            Label(isExporting ? "Generating…" : "Save Image", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain).disabled(isExporting)

                        Button {
                            copyToClipboard()
                        } label: {
                            Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                                .font(.system(size: 12))
                                .foregroundColor(.accentColor)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        if !exportMessage.isEmpty {
                            Text(exportMessage)
                                .font(.system(size: 10)).foregroundColor(.green)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(width: 180)
            }
            .padding(20)
        }
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // ── Card preview ──────────────────────────────────────────────────────────

    @ViewBuilder
    var cardPreview: some View {
        switch selectedPalette {
        case .dark:    StudyCard(style: selectedStyle, bg: [Color(red:0.05,green:0.05,blue:0.12), Color(red:0.02,green:0.02,blue:0.08)], accent: .blue)
        case .neon:    StudyCard(style: selectedStyle, bg: [Color(red:0.0,green:0.0,blue:0.05), Color.black], accent: Color(red:0.2,green:1,blue:0.5))
        case .minimal: StudyCard(style: selectedStyle, bg: [Color(red:0.97,green:0.97,blue:1.0), Color.white], accent: .indigo)
        }
    }

    // ── Export ────────────────────────────────────────────────────────────────

    func renderCard() -> NSImage? {
        let hostingView: NSView
        switch selectedPalette {
        case .dark:    hostingView = NSHostingView(rootView: StudyCard(style: selectedStyle, bg: [Color(red:0.05,green:0.05,blue:0.12), Color(red:0.02,green:0.02,blue:0.08)], accent: .blue).frame(width: 1080, height: 1080))
        case .neon:    hostingView = NSHostingView(rootView: StudyCard(style: selectedStyle, bg: [Color(red:0.0,green:0.0,blue:0.05), Color.black], accent: Color(red:0.2,green:1,blue:0.5)).frame(width: 1080, height: 1080))
        case .minimal: hostingView = NSHostingView(rootView: StudyCard(style: selectedStyle, bg: [Color(red:0.97,green:0.97,blue:1.0), Color.white], accent: .indigo).frame(width: 1080, height: 1080))
        }
        hostingView.frame = NSRect(x: 0, y: 0, width: 1080, height: 1080)
        hostingView.wantsLayer = true

        let image = NSImage(size: NSSize(width: 1080, height: 1080))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            hostingView.layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    func exportCard() {
        isExporting = true
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title           = "Save Study Card"
        panel.nameFieldStringValue = "StudyNotch-\(selectedStyle.rawValue.lowercased())-card.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            if let img = renderCard(),
               let tiff = img.tiffRepresentation,
               let rep  = NSBitmapImageRep(data: tiff),
               let png  = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                exportMessage = "✓ Saved to \(url.lastPathComponent)"
            }
        }
        isExporting = false
    }

    func copyToClipboard() {
        guard let img = renderCard() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        exportMessage = "✓ Copied! Paste anywhere (Instagram, iMessage…)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exportMessage = "" }
    }
}

// ── Study Card ────────────────────────────────────────────────────────────────

struct StudyCard: View {
    let style    : ShareCardView.CardStyle
    let bg       : [Color]
    let accent   : Color

    @Bindable var sessions = SessionStore.shared
    @Bindable var subStore = SubjectStore.shared
    var isDark: Bool { bg.first?.description.contains("0.05") ?? true }

    var textColor: Color  { isDark ? .white : Color(red:0.1,green:0.1,blue:0.15) }
    var subColor:  Color  { isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.4) }

    var todayHours: Double {
        let cal = Calendar.current
        return sessions.sessions
            .filter { cal.isDateInToday($0.startTime) }
            .reduce(0) { $0 + $1.duration } / 3600
    }

    var weekHours: Double {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        return sessions.sessions
            .filter { $0.startTime > cutoff }
            .reduce(0) { $0 + $1.duration } / 3600
    }

    var streak: Int {
        let cal = Calendar.current; var n = 0; var day = Date()
        while sessions.sessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1; day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var topSubjects: [(String, Double)] {
        Array(sessions.subjectTotals.prefix(3).map { ($0.subject, $0.total / 3600) })
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(colors: bg, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Logo + app name
                HStack {
                    Circle().fill(accent).frame(width: 16, height: 16)
                    Text("StudyNotch").font(.system(size: 14, weight: .bold)).foregroundColor(textColor.opacity(0.6))
                    Spacer()
                    Text(Date().formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.system(size: 11)).foregroundColor(subColor)
                }
                .padding(.horizontal, 24).padding(.top, 24)

                Spacer()

                // Main stat
                VStack(spacing: 6) {
                    switch style {
                    case .today:
                        mainStat(String(format: "%.1f", todayHours), "hours", "studied today", accent)
                    case .week:
                        mainStat(String(format: "%.0f", weekHours), "hours", "this week", accent)
                    case .streak:
                        mainStat("\(streak)", "day", streak == 1 ? "streak 🔥" : "streak 🔥🔥", .orange)
                    }
                }

                Spacer()

                // Subject pills
                if !topSubjects.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(topSubjects, id: \.0) { sub, hours in
                            HStack(spacing: 4) {
                                Circle().fill(subStore.color(for: sub)).frame(width: 6, height: 6)
                                Text(sub).font(.system(size: 10, weight: .semibold)).foregroundColor(textColor.opacity(0.8))
                                Text(String(format: "%.0fh", hours))
                                    .font(.system(size: 9)).foregroundColor(subColor)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(textColor.opacity(0.06))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Tagline
                Text("📚 Focused. Consistent. Growing.")
                    .font(.system(size: 10)).foregroundColor(subColor)
                    .padding(.bottom, 24).padding(.top, 12)
            }
        }
    }

    func mainStat(_ value: String, _ unit: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(color.opacity(0.7))
                    .padding(.bottom, 10)
            }
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(textColor.opacity(0.6))
        }
    }
}
