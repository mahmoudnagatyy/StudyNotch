import SwiftUI
import AppKit

// ── Brain View ────────────────────────────────────────────────────────────────
//  Tab 4 in the 4-tab structure.
//  Sections: AI Coach → Notes
//  No nested tabs — scroll view.

struct BrainTabView: View {
    var ai       = AIService.shared
    @Bindable var sessions = SessionStore.shared
    @State private var expandedSection: Set<String> = ["ai", "notes"]
    @State private var apiKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("AI Coach", key: "ai", icon: "brain.head.profile", color: .purple)
                if expandedSection.contains("ai") { aiSection }

                sectionHeader("Calendar", key: "calendar", icon: "calendar.badge.checkmark", color: .blue)
                if expandedSection.contains("calendar") {
                    CalendarDebugView()
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }

                sectionHeader("Notes", key: "notes", icon: "note.text", color: .blue)
                if expandedSection.contains("notes") { notesSection }
            }
        }
    }

    // ── Section header ────────────────────────────────────────────────────────

    func sectionHeader(_ title: String, key: String, icon: String, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if expandedSection.contains(key) { expandedSection.remove(key) }
                else { expandedSection.insert(key) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: expandedSection.contains(key) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(color.opacity(0.04))
        }
        .buttonStyle(.plain)
    }

    // ── AI Section ────────────────────────────────────────────────────────────

    var aiSection: some View {
        VStack(spacing: 12) {
            // API key
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "key.fill").font(.system(size: 10)).foregroundColor(.orange)
                    Text("Groq API Key").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    SecureField("Paste key from console.groq.com", text: $apiKey)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11))
                        .onChange(of: apiKey) { UserDefaults.standard.set($0, forKey: "groq_api_key") }
                    Button("Get Free Key") {
                        NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
                    }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.accentColor)
                }
                Text("Free · No credit card · 14,400 req/day")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            .padding(12).background(Color.orange.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))

            // AI tools grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                aiTool(
                    "Smart Schedule", "calendar.badge.plus", .blue,
                    loading: ai.isLoadingSchedule, result: ai.scheduleResult
                ) { ai.generateSchedule() }

                aiTool(
                    "Weekly Report", "chart.line.uptrend.xyaxis", .purple,
                    loading: ai.isLoadingReport, result: ai.reportResult
                ) { ai.generateWeeklyReport() }

                aiTool(
                    "Study Style", "person.fill.questionmark", .teal,
                    loading: ai.isLoadingStyle, result: ai.styleResult
                ) { ai.detectStudyStyle() }

                aiTool(
                    "Session Length", "stopwatch", .cyan,
                    loading: ai.isAnalysingLength, result: ai.sessionLengthInsight
                ) { ai.analyseSessionLength() }
            }

            // AI Acts
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill").foregroundColor(.green)
                    Text("AI Actions").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("AI adjusts your plan directly").font(.system(size: 10)).foregroundColor(.secondary)
                }

                if !ai.planAdjustResult.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(ai.planAdjustResult.components(separatedBy: "\n").filter { !$0.isEmpty }, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 10)).foregroundColor(.green)
                                Text(line).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(10).background(Color.green.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("✓ Apply to Weekly Plan") {
                        ai.autoAdjustPlan { adjustments in
                            for (subject, newHours, _) in adjustments {
                                SubjectStore.shared.setWeeklyGoal(subject: subject, hours: newHours)
                            }
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.green.opacity(0.1)).clipShape(Capsule())
                }

                Button(ai.isAdjustingPlan ? "Analysing…" : "🤖 Auto-Adjust My Plan") {
                    ai.autoAdjustPlan { _ in }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 7)
                .background(ai.isAdjustingPlan ? Color.secondary.opacity(0.3) : Color.green)
                .clipShape(Capsule()).disabled(ai.isAdjustingPlan)
            }
            .padding(14).background(Color.green.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    func aiTool(_ title: String, _ icon: String, _ color: Color,
                loading: Bool, result: String,
                action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(color).font(.system(size: 14))
                Spacer()
                if loading { ProgressView().scaleEffect(0.6) }
            }
            Text(title).font(.system(size: 12, weight: .semibold))
            if result.isEmpty {
                Button("Generate") { action() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(color.opacity(0.12)).clipShape(Capsule())
                    .disabled(loading)
            } else {
                ScrollView {
                    Text(result).font(.system(size: 10)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                Button("Regenerate") { action() }
                    .buttonStyle(.plain).font(.system(size: 9)).foregroundColor(color).disabled(loading)
            }
        }
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.12), lineWidth: 0.5))
    }

    // ── Notes Section ─────────────────────────────────────────────────────────

    var notesSection: some View {
        VStack(spacing: 0) {
            let notes = SessionStore.shared.quickNotes
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text").font(.system(size: 30)).foregroundColor(.secondary.opacity(0.3))
                    Text("No notes yet — use the quick note field in the notch")
                        .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ForEach(notes) { note in
                    noteRow(note)
                    Divider().padding(.leading, 16)
                }
            }
        }
        .padding(.bottom, 16)
    }

    func noteRow(_ note: QuickNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !note.subject.isEmpty {
                        Circle().fill(SubjectStore.shared.color(for: note.subject)).frame(width: 7, height: 7)
                        Text(note.subject).font(.system(size: 10, weight: .semibold))
                            .foregroundColor(SubjectStore.shared.color(for: note.subject))
                    }
                    Text(note.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    if note.sentToTelegram {
                        Image(systemName: "paperplane.fill").font(.system(size: 9))
                            .foregroundColor(Color(red:0.25,green:0.72,blue:1))
                    }
                }
                if !note.text.isEmpty {
                    Text(note.text).font(.system(size: 12)).foregroundColor(.primary).lineLimit(3)
                }
                if let imgData = note.imageData, let img = NSImage(data: imgData) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer()
            Button { SessionStore.shared.deleteQuickNote(note) } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
