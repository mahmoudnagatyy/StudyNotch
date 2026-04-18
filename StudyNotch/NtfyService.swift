import Foundation
import Observation
import SwiftUI
import Observation

// ── ntfy.sh iPhone Push Service ───────────────────────────────────────────────
//
//  ntfy.sh is a free, open-source push notification relay.
//  No account needed — just pick a unique topic name.
//
//  SETUP (30 seconds):
//  1. On your iPhone: install "ntfy" from the App Store (free)
//  2. Open ntfy → tap "+" → enter your topic name (e.g. "mahmoud-studynotch-abc123")
//     Use something random enough that others won't accidentally subscribe.
//  3. Paste the same topic name into StudyNotch → Plan → Notifications → iPhone
//  4. That's it. Every notification StudyNotch fires will also arrive on your iPhone.
//
//  HOW IT WORKS:
//  The Mac app sends an HTTP POST to https://ntfy.sh/<topic>.
//  ntfy.sh relays it as a push notification to all subscribed devices.
//  All traffic is end-to-end via HTTPS. ntfy.sh is open-source (github.com/binwiederhier/ntfy).
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class NtfyService {
    static let shared = NtfyService()

     var topic     : String = UserDefaults.standard.string(forKey: "ntfy_topic")  ?? ""
     var isEnabled : Bool   = UserDefaults.standard.bool(forKey: "ntfy_enabled")

    // ntfy.sh supports custom servers — default is the public one
     var serverURL : String = UserDefaults.standard.string(forKey: "ntfy_server") ?? "https://ntfy.sh"

    var isConfigured: Bool { isEnabled && !topic.trimmingCharacters(in: .whitespaces).isEmpty }

    // ── Persistence ───────────────────────────────────────────────────────────

    func save() {
        let t = topic.trimmingCharacters(in: .whitespaces)
        topic = t
        UserDefaults.standard.set(t,         forKey: "ntfy_topic")
        UserDefaults.standard.set(isEnabled, forKey: "ntfy_enabled")
        UserDefaults.standard.set(serverURL, forKey: "ntfy_server")
    }

    // ── Send ──────────────────────────────────────────────────────────────────

    func send(title: String, body: String, priority: NtfyPriority = .default, tags: [String] = []) {
        guard isConfigured else { return }
        let topicClean = topic.trimmingCharacters(in: .whitespaces)
        let base       = serverURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url  = URL(string: "\(base)/\(topicClean)") else { return }

        var req          = URLRequest(url: url)
        req.httpMethod   = "POST"
        req.setValue(body,                      forHTTPHeaderField: "Content-Type")   // body as plain text
        req.setValue(title,                     forHTTPHeaderField: "Title")
        req.setValue(priority.rawValue,         forHTTPHeaderField: "Priority")
        if !tags.isEmpty {
            req.setValue(tags.joined(separator: ","), forHTTPHeaderField: "Tags")
        }
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { _, response, error in
            if let e = error { print("[ntfy] send error: \(e.localizedDescription)") }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("[ntfy] HTTP \(http.statusCode)")
            }
        }.resume()
    }

    /// Send a test notification
    func sendTest(completion: @escaping (Bool, String) -> Void) {
        guard isConfigured else {
            completion(false, "No topic set"); return
        }
        let topicClean = topic.trimmingCharacters(in: .whitespaces)
        let base       = serverURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url  = URL(string: "\(base)/\(topicClean)") else {
            completion(false, "Invalid URL"); return
        }
        var req        = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("StudyNotch Test 🎓",          forHTTPHeaderField: "Title")
        req.setValue("high",                          forHTTPHeaderField: "Priority")
        req.setValue("white_check_mark,iphone",       forHTTPHeaderField: "Tags")
        req.httpBody   = "StudyNotch is successfully connected to your iPhone!".data(using: .utf8)
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if let e = error { completion(false, e.localizedDescription); return }
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                completion(ok, ok ? "✓ Delivered!" : "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        }.resume()
    }
}

// ── Priority ──────────────────────────────────────────────────────────────────

enum NtfyPriority: String {
    case min     = "min"
    case low     = "low"
    case `default` = "default"
    case high    = "high"
    case urgent  = "urgent"
}

// ── iPhone Settings Section ───────────────────────────────────────────────────

struct IPhoneNotificationSection: View {
    @Bindable var svc = NtfyService.shared
    @State private var testStatus = ""
    @State private var testing    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(red: 0.3, green: 0.7, blue: 1).opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12)).foregroundColor(Color(red: 0.3, green: 0.7, blue: 1))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("iPhone Notifications").font(.system(size: 13, weight: .semibold))
                    Text("Push to your iPhone via ntfy.sh (free, no account needed)")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $svc.isEnabled).labelsHidden()
            }

            if svc.isEnabled {
                Divider()

                // Setup steps
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick setup:")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    stepRow(1, "Install the free \"ntfy\" app on your iPhone from the App Store")
                    stepRow(2, "Open ntfy → tap \"+\" → enter your topic name below")
                    stepRow(3, "Tap the Test button to confirm it works")
                }

                Divider()

                // Topic field
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Topic name").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        TextField("e.g. mahmoud-study-abc123", text: $svc.topic)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Server (collapsed by default — only advanced users need this)
                DisclosureGroup {
                    HStack(spacing: 8) {
                        Text("Server").font(.system(size: 11)).foregroundColor(.secondary).frame(width: 50)
                        TextField("https://ntfy.sh", text: $svc.serverURL)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Custom server (optional)").font(.system(size: 10)).foregroundColor(.secondary)
                }

                // Save + Test
                HStack(spacing: 10) {
                    Button {
                        svc.save()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                            Text("Save").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(red: 0.2, green: 1.0, blue: 0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        svc.save()
                        testing = true; testStatus = ""
                        svc.sendTest { ok, msg in
                            testing = false
                            testStatus = msg
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { testStatus = "" }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if testing {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "paperplane.fill").font(.system(size: 11))
                            }
                            Text("Send Test").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(red: 0.3, green: 0.7, blue: 1))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(red: 0.3, green: 0.7, blue: 1).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(svc.topic.trimmingCharacters(in: .whitespaces).isEmpty || testing)

                    if !testStatus.isEmpty {
                        Text(testStatus)
                            .font(.system(size: 11))
                            .foregroundColor(testStatus.hasPrefix("✓") ? .green : .red)
                            .transition(.opacity)
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(svc.isConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(svc.isConfigured ? "Configured" : "Not configured")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Color(red: 0.3, green: 0.7, blue: 1).opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(red: 0.3, green: 0.7, blue: 1).opacity(0.15), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.2), value: svc.isEnabled)
    }

    func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.3, green: 0.7, blue: 1))
                .frame(width: 14)
            Text(text).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
