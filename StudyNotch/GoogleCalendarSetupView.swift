import SwiftUI
import AppKit

// ── Google Calendar Setup View ────────────────────────────────────────────────
//
//  Shown inside Analytics → Settings card.
//  Three states: credentials entry → authorization → connected.

struct GoogleCalendarSetupView: View {
    @Bindable var gcal = GoogleCalendarService.shared
    @Bindable var sessions = SessionStore.shared
    @State private var clientIDInput     = UserDefaults.standard.string(forKey: "gcal.clientID")     ?? ""
    @State private var clientSecretInput = UserDefaults.standard.string(forKey: "gcal.clientSecret") ?? ""
    @State private var authCode          = ""
    @State private var showCredentials   = false
    @State private var showAuthStep      = false
    @State private var syncResult        = ""
    @State private var showGuide         = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundColor(gcal.isConnected ? .green : Color(red:0.25,green:0.72,blue:1))
                Text("Google Calendar Sync")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                if gcal.isConnected {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Connected").font(.system(size: 11)).foregroundColor(.green.opacity(0.8))
                    }
                    Toggle("Auto-sync", isOn: $gcal.autoSync)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            // ── Setup guide (collapsible) ─────────────────────────────────────
            DisclosureGroup(isExpanded: $showGuide) {
                VStack(alignment: .leading, spacing: 5) {
                    guideRow("1", "Go to console.cloud.google.com → New Project → \"StudyNotch\"")
                    guideRow("2", "APIs & Services → Enable → search \"Google Calendar API\" → Enable")
                    guideRow("3", "OAuth consent screen → External → add your Gmail as test user → Save")
                    guideRow("4", "Credentials → Create → OAuth 2.0 Client ID → Desktop App → Create")
                    guideRow("5", "Copy the Client ID and Client Secret → paste below → Save Credentials")
                    guideRow("6", "Click Connect → browser opens → sign in → it connects automatically")
                    Button("Open Google Cloud Console ↗") {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red:0.25,green:0.72,blue:1))
                }
                .padding(.top, 6)
            } label: {
                Text(showGuide ? "Hide setup guide" : "▸ How to get credentials (one-time, ~5 min)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }

            Divider().overlay(Color.white.opacity(0.08))

            if !gcal.isConnected {
                // ── Step 1: Credentials ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step 1 — Google Cloud credentials")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Client ID").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                            TextField("xxxx.apps.googleusercontent.com", text: $clientIDInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Client Secret").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                            SecureField("GOCSPX-…", text: $clientSecretInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 130)
                        }
                        Button("Save") {
                            gcal.setCredentials(clientID: clientIDInput, clientSecret: clientSecretInput)
                            showAuthStep = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red:0.2,green:1,blue:0.5))
                        .padding(.top, 14)
                        .disabled(clientIDInput.isEmpty || clientSecretInput.isEmpty)
                    }
                }

                // ── Step 2: Authorize ─────────────────────────────────────────
                if showAuthStep || !clientIDInput.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Step 2 — Authorize access")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))

                        HStack(spacing: 8) {
                            Button("Connect →") {
                                gcal.setCredentials(clientID: clientIDInput, clientSecret: clientSecretInput)
                                gcal.authenticate()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color(red:0.25,green:0.72,blue:1))
                            .clipShape(Capsule())

                            Text(gcal.status).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }

            } else {
                // ── Connected state ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {

                    // Explanation of what gets synced
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 10))
                            .foregroundColor(Color(red:0.25,green:0.72,blue:1).opacity(0.7))
                        Text("Only planned sessions (future start time) are pushed. Use ⌘⌥M → set a future date to schedule study time.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color(red:0.25,green:0.72,blue:1).opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        // Status
                        Text(gcal.status)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        if let last = gcal.lastSyncDate {
                            Text("Last sync: \(last.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        // Test with one session first
                    Button("Test (1 session)") {
                            testOne()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color(red:0.2,green:1,blue:0.5))
                        .clipShape(Capsule())
                        .disabled(gcal.isSyncing || futureSessions.isEmpty)

                    Button(gcal.isSyncing ? "Syncing…" : "Sync Planned Sessions →") {
                            syncAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(gcal.isSyncing
                            ? Color.white.opacity(0.3)
                            : Color(red:0.25,green:0.72,blue:1))
                        .clipShape(Capsule())
                        .disabled(gcal.isSyncing || futureSessions.isEmpty)

                        Text("\(futureSessions.count) planned session\(futureSessions.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundColor(futureSessions.isEmpty ? .orange : .white.opacity(0.3))

                        Spacer()

                        Button("Disconnect") { gcal.disconnect() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.5))
                    }

                    // Sync result feedback
                    if !syncResult.isEmpty {
                        Text(syncResult)
                            .font(.system(size: 10))
                            .foregroundColor(syncResult.hasPrefix("✓") ? .green : .orange)
                    }

                    // Last API error — shows exact Google error message
                    if !gcal.lastError.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red).font(.system(size: 10))
                                Text("API Error").font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                                Spacer()
                                Button("Dismiss") { gcal.lastError = "" }
                                    .buttonStyle(.plain).font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            Text(gcal.lastError)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.red.opacity(0.85))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Reconnect button if token expired
                    if gcal.status.contains("reconnect") || gcal.status.contains("expired") {
                        Button("Reconnect Google Calendar →") {
                            gcal.disconnect()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    func exchangeCode() {
        guard !authCode.isEmpty else { return }
        gcal.exchangeCode(authCode) { success in
            if !success { authCode = "" }
        }
    }

    var futureSessions: [StudySession] {
        sessions.sessions.filter { $0.startTime > Date() }
    }

    func testOne() {
        // Only push a planned/future-dated session
        guard let first = futureSessions.first else {
            syncResult = "⚠ No planned sessions found. Log a future session first."
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { syncResult = "" }
            return
        }
        gcal.lastError = ""
        gcal.pushSession(first) { ok in
            syncResult = ok
                ? "✓ Pushed \"\(first.subject)\" to Google Calendar"
                : "✗ Failed — see error below"
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { syncResult = "" }
        }
    }

    func syncAll() {
        let planned = futureSessions
        guard !planned.isEmpty else {
            syncResult = "⚠ No planned (future-dated) sessions to push."
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { syncResult = "" }
            return
        }
        gcal.syncAll(sessions: planned) { pushed, failed in
            if failed == 0 {
                syncResult = "✓ Pushed \(pushed) planned sessions to Google Calendar"
            } else {
                syncResult = "⚠ \(pushed) succeeded, \(failed) failed"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { syncResult = "" }
        }
    }

    func guideRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red:0.25,green:0.72,blue:1))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
