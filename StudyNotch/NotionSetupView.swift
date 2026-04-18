import SwiftUI

// ── Notion Setup View ─────────────────────────────────────────────────────────
//
//  Shown inside Analytics → AI Coach → Settings card
//  Guides user through: API key → root page ID → test connection

struct NotionSetupView: View {
    @Bindable var notion = NotionService.shared
    @State private var keyInput    = ""
    @State private var pageInput   = ""
    @State private var testResult  = ""
    @State private var testing     = false
    @State private var showKey     = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Step 1: API Key ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("1", "Notion API Key")
                HStack(spacing: 6) {
                    Group {
                        if showKey {
                            TextField("secret_...", text: $keyInput)
                        } else {
                            SecureField("secret_...", text: $keyInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: keyInput) { v in
                        let clean = v.trimmingCharacters(in: .whitespaces)
                        notion.apiKey = clean
                    }

                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Get free key at notion.so/my-integrations →") {
                    NSWorkspace.shared.open(URL(string: "https://www.notion.so/my-integrations")!)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.accentColor)

                Text("Create an integration → copy the Internal Integration Secret")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            // ── Step 2: Root Page ID ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("2", "Root Page ID")
                TextField("Paste Notion page ID or URL", text: $pageInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onChange(of: pageInput) { v in
                        notion.rootPageID = extractPageID(v)
                    }

                Text("Open a Notion page → Share → Copy link. Paste the full URL or just the ID.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !notion.rootPageID.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 10))
                        Text("Page ID: " + notion.rootPageID.prefix(8) + "…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Text("⚠️ Share that page with your integration: Open page → Share → Invite → select your integration")
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // ── Step 3: Test ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                stepLabel("3", "Test Connection")
                HStack(spacing: 8) {
                    Button(testing ? "Testing…" : "Test Connection") {
                        testing = true
                        testResult = ""
                        notion.testConnection { ok, msg in
                            testing   = false
                            testResult = msg
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(notion.apiKey.isEmpty ? Color.secondary.opacity(0.3) : Color.accentColor)
                    .clipShape(Capsule())
                    .disabled(notion.apiKey.isEmpty || testing)

                    if notion.isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 11))
                            Text("Connected").font(.system(size: 11)).foregroundColor(.green)
                        }
                    }
                }

                if !testResult.isEmpty {
                    Text(testResult)
                        .font(.system(size: 10))
                        .foregroundColor(testResult.hasPrefix("✓") ? .green : .red.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !notion.lastError.isEmpty {
                    Text(notion.lastError)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.red.opacity(0.7))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            // ── Status / cache ────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button("Clear page cache") {
                    notion.clearCache()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                Spacer()

                Text("Pages auto-created per subject on first use")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .onAppear {
            keyInput  = notion.apiKey
            pageInput = notion.rootPageID
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func stepLabel(_ n: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                Text(n).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
            }
            Text(title).font(.system(size: 12, weight: .semibold))
        }
    }

    /// Extract just the 32-char page ID from a Notion URL or raw ID
    func extractPageID(_ input: String) -> String {
        let s = input.trimmingCharacters(in: .whitespaces)
        // Full URL: notion.so/Page-Title-abc123def456...
        // or notion.so/workspace/abc123def456...
        // The page ID is the last 32 hex chars (may have hyphens)
        let stripped = s.replacingOccurrences(of: "-", with: "")
        // Find a 32-char hex sequence
        if let range = stripped.range(of: "[0-9a-f]{32}", options: .regularExpression) {
            return String(stripped[range])
        }
        // Already a clean ID?
        let clean = s.replacingOccurrences(of: "-", with: "")
        if clean.count == 32 { return clean }
        return s
    }
}
