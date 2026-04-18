import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Header
            HStack(spacing: 20) {
                tabButton(0, "keyboard", "General")
                tabButton(1, "bell.badge", "Notifications")
                tabButton(2, "brain.head.profile", "AI Coach")
                tabButton(3, "link", "Integrations")
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            .background(Color.black.opacity(0.2))
            
            Divider().overlay(Color.white.opacity(0.1))
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if selectedTab == 0 { generalTab }
                    else if selectedTab == 1 { notificationsTab }
                    else if selectedTab == 2 { aiTab }
                    else if selectedTab == 3 { integrationsTab }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }
    
    func tabButton(_ idx: Int, _ icon: String, _ label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = idx }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(selectedTab == idx ? .accentColor : .secondary)
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
    
    // ── GENERAL TAB ──────────────────────────────────────────────────────────
    
    var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("App Preferences", icon: "slider.horizontal.3")
            
            // Mode Select
            VStack(alignment: .leading, spacing: 8) {
                Text("Study Mode").font(.system(size: 13, weight: .semibold))
                Text("College mode tracks specific subjects/credits. Free mode is flexible.").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { ModeStore.shared.currentMode },
                    set: { ModeStore.shared.currentMode = $0 }
                )) {
                    ForEach(StudyMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            // Sound Theme
            VStack(alignment: .leading, spacing: 8) {
                Text("Sound Theme").font(.system(size: 13, weight: .semibold))
                Text("Choose your session start/end and milestone chimes.").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { SoundService.shared.theme },
                    set: { SoundService.shared.theme = $0 }
                )) {
                    ForEach(SoundTheme.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            // Voice Control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Control").font(.system(size: 13, weight: .semibold))
                        Text("Control sessions with voice (e.g. 'Start study').").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { VoiceCommandService.shared.isEnabled },
                        set: { 
                            VoiceCommandService.shared.isEnabled = $0
                            if $0 { VoiceCommandService.shared.requestPermission() }
                        }
                    ))
                    .toggleStyle(.switch)
                }
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            // Seasonal Theme
            VStack(alignment: .leading, spacing: 8) {
                Text("Seasonal Theme").font(.system(size: 13, weight: .semibold))
                Text("Override the automatically detected season.").font(.system(size: 11)).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { ThemeService.shared.userOverride ?? .none },
                    set: { ThemeService.shared.userOverride = ($0 == .none ? nil : $0) }
                )) {
                    Text("Auto-detect").tag(AppSeason.none)
                    Divider()
                    ForEach(AppSeason.allCases.filter({ $0 != .none }), id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            // iCloud Sync
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync").font(.system(size: 13, weight: .semibold))
                        Text("Sync your study sessions across your devices.").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { CloudSyncService.shared.enabled },
                        set: { 
                            CloudSyncService.shared.enabled = $0
                            if $0 { 
                                CloudSyncService.shared.setup()
                                CloudSyncService.shared.mergeFromCloud()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            // Backup & Data Management
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup & Data Management").font(.system(size: 13, weight: .semibold))
                    Text("Your data is saved in a system folder. Export it safely before moving to a new Mac.").font(.system(size: 11)).foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Button(action: {
                        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("StudyNotch", isDirectory: true)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }) {
                        Label("Show Data in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        let source = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("StudyNotch", isDirectory: true)
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                        let dest = docs.appendingPathComponent("StudyNotch_Backup_\(dateFormatter.string(from: Date()))")
                        do {
                            try FileManager.default.copyItem(at: source, to: dest)
                            let alert = NSAlert()
                            alert.messageText = "Backup Successful"
                            alert.informativeText = "Your data has been backed up to your Documents folder:\n\(dest.path)"
                            alert.runModal()
                            NSWorkspace.shared.activateFileViewerSelecting([dest])
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Backup Failed"
                            alert.informativeText = "Could not create backup: \(error.localizedDescription)"
                            alert.runModal()
                        }
                    }) {
                        Label("Export Backup to Documents", systemImage: "archivebox")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // ── NOTIFICATIONS TAB ────────────────────────────────────────────────────
    
    var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotificationSettingsSection()
        }
    }
    
    // ── AI COACH TAB ─────────────────────────────────────────────────────────
    
    var aiTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("AI Coach (Groq)", icon: "sparkles")
            
            VStack(alignment: .leading, spacing: 12) {
                Text("API Key").font(.system(size: 13, weight: .semibold))
                SecureField("gsk_...", text: Binding(
                    get: { AIService.shared.apiKey() },
                    set: { AIService.shared.saveKey($0) }
                ))
                .textFieldStyle(.roundedBorder)
                
                Button("Get free Groq key →") {
                    NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(.accentColor)
                
                Text("Model Selection").font(.system(size: 13, weight: .semibold)).padding(.top, 8)
                Picker("", selection: Binding(
                    get: { AIService.shared.selectedModel },
                    set: { AIService.shared.selectedModel = $0 }
                )) {
                    Text("Llama 3 8B (Fast)").tag("llama3-8b-8192")
                    Text("Llama 3 70B (Smart)").tag("llama3-70b-8192")
                    Text("Mixtral 8x7B").tag("mixtral-8x7b-32768")
                }
                .pickerStyle(.menu)
            }
            
            Divider().overlay(Color.white.opacity(0.05))
            
            Text("AI Coach uses your session data to provide personalized study tips on the Today screen and via the Chat interface.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
    
    // ── INTEGRATIONS TAB ─────────────────────────────────────────────────────
    
    var integrationsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("External Integrations", icon: "link")
            
            // Notion
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Notion Bridge").font(.system(size: 14, weight: .bold))
                    Spacer()
                    if NotionService.shared.isConnected {
                        Text("Connected").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15)).clipShape(Capsule())
                    }
                }
                NotionSetupView()
            }
            .padding(16).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Google Calendar
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Google Calendar").font(.system(size: 14, weight: .bold))
                    Spacer()
                    if GoogleCalendarService.shared.isConnected {
                        Text("Connected").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15)).clipShape(Capsule())
                    }
                }
                Button(GoogleCalendarService.shared.isConnected ? "Disconnect" : "Connect Account") {
                    if GoogleCalendarService.shared.isConnected { GoogleCalendarService.shared.disconnect() }
                    else { GoogleCalendarService.shared.authenticate() }
                }
                .buttonStyle(.bordered).tint(GoogleCalendarService.shared.isConnected ? .red : .blue)
            }
            .padding(16).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
            
            // iPhone Push
            IPhoneNotificationSection()
        }
    }
    
    func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(.accentColor)
            Text(title).font(.system(size: 14, weight: .bold))
        }
    }
}

class SettingsWindowController: NSWindowController {
    static var shared: SettingsWindowController?
    
    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Settings"
        win.center()
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)
        win.contentView = NSHostingView(rootView: SettingsView())
        
        shared = SettingsWindowController(window: win)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
            shared = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
