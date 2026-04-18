import AppKit
import SwiftUI
import Network

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Defer UI setup one run-loop tick so AppKit fully processes the
        // activation policy before NSStatusBar and NSWindow calls are made.
        DispatchQueue.main.async {
            NotchWindowController.show()
            self.setupMenuBar()
            self.setupGlobalShortcut()
            WebServer.shared.start()
            // One-time dedup of case-variant subject names (e.g. "Cyber" vs "cyber")
            SessionStore.shared.deduplicateSubjects()

            // Seed subject color metas for all known subjects so dot color
            // is correct immediately on launch without running a session first
            let store = SubjectStore.shared
            let known = SessionStore.shared.knownSubjects
            for s in known { store.ensureMeta(for: s) }
            // Pre-seed currentSubject from last session so dot shows right away
            if let last = SessionStore.shared.sessions.first {
                StudyTimer.shared.currentSubject = last.subject
            }
            // Seed persistent color metas for ALL known subjects so colors never change
            let allSubjects: [String] = {
                var s = SessionStore.shared.knownSubjects
                for sub in ModeStore.shared.collegeSubjects.map(\.name) {
                    if !s.contains(sub) { s.append(sub) }
                }
                return s.filter { !$0.isEmpty }
            }()
            SubjectStore.shared.seedAllMetas(subjects: allSubjects)
            // Boot notification service (requests permission + schedules reminders)
            NotificationService.shared.start()
            // Request iCloud calendar access (non-blocking)
            CalendarDebugService.shared.requestiCloudAccess()
            // Seed streak data from existing sessions
            StreakStore.shared.rebuild()
        }
    }

    // ── Menu Bar ──────────────────────────────────────────────────────────────

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Use the custom app icon scaled to menu bar size
        if let iconURL  = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            iconImage.size = NSSize(width: 18, height: 18)
            statusItem?.button?.image = iconImage
        } else {
            statusItem?.button?.image = NSImage(systemSymbolName: "graduationcap.fill",
                                                accessibilityDescription: "StudyNotch")
        }

        // ── Main app menu (provides ⌘C/⌘V/⌘A to all text fields) ─────────────
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit StudyNotch", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu — critical for ⌘C, ⌘V, ⌘A, ⌘Z in text fields
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",        action: Selector(("undo:")),         keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",        action: Selector(("redo:")),         keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut",         action: #selector(NSText.cut(_:)),   keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",        action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",       action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",  action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu

        // ── Status bar menu ───────────────────────────────────────────────────
        let menu = NSMenu()
        menu.addItem(withTitle: "▶  Start / Pause       ⌘⌥T", action: #selector(toggleTimer),   keyEquivalent: "")
        menu.addItem(withTitle: "⏹  Finish Session      ⌘⌥F", action: #selector(finishSession), keyEquivalent: "")
        menu.addItem(withTitle: "↺  Reset               ⌘⌥R", action: #selector(resetTimer),    keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "↗️  Log Manual Session  ⌘⌥M", action: #selector(logManualSession), keyEquivalent: "")
        menu.addItem(withTitle: "🎯  Log Current App       ⌘⌥L", action: #selector(logCurrentApp), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "📊  Analytics          ⌘⌥S", action: #selector(showAnalytics), keyEquivalent: "")
        menu.addItem(withTitle: "🗓  Today               ⌘⌥D", action: #selector(showToday),      keyEquivalent: "")
        menu.addItem(withTitle: "📅  Study Plan          ⌘⌥P", action: #selector(showStudyPlan),  keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        // iPhone dashboard — shows the local URL
        let iphoneItem = NSMenuItem(title: "📱  Open on iPhone…", action: #selector(showIPhoneURL), keyEquivalent: "")
        iphoneItem.target = self
        menu.addItem(iphoneItem)
        menu.addItem(withTitle: "⚙️  Settings…",             action: #selector(showSettings),       keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit",                     action: #selector(quitApp),       keyEquivalent: "q")

        for item in menu.items { item.target = self }
        statusItem?.menu = menu
    }

    @objc func toggleTimer()   { StudyTimer.shared.toggle() }
    @objc func resetTimer()    { StudyTimer.shared.reset()  }
    @objc func showAnalytics()      { AnalyticsWindowController.show() }
    @objc func showToday()          { TodayWindowController.show() }
    @objc func showShareCard()      {
        NSApp.activate(ignoringOtherApps: true)
        let win = NSWindow(
            contentRect: NSRect(x:0, y:0, width:480, height:360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "Share Study Card"
        win.titlebarAppearsTransparent = true
        win.center()
        win.contentView = NSHostingView(rootView: ShareCardView())
        win.makeKeyAndOrderFront(nil)
    }
    @objc func showAIChat()         { AIChatWindowController.show() }
    @objc func showGoogleCalendar()  { AnalyticsWindowController.show() }  // opens Analytics; user navigates to AI Coach → Google Calendar
    @objc func showStudyPlan() { StudyPlanWindowController.show() }
    @objc func showTasks()     { StudyPlanWindowController.showTasks() }
    @objc func showSubjectSettings() { SubjectSettingsWindowController.show() }
    @objc func logManualSession() { SessionEndWindowController.presentManual() }
    @objc func logCurrentApp() { AutoSessionDetector.shared.logManualSession() }


    @objc func showSettings() {
        SettingsWindowController.show()
    }

    @objc func quitApp()       { WebServer.shared.stop(); NSApp.terminate(nil) }

    @objc func showIPhoneURL() {
        PhoneAccessWindowController.show()
    }

    @objc func finishSession() {
        if let data = StudyTimer.shared.finish() {
            SessionEndWindowController.present(sessionData: data)
        }
    }

    // ── Global Shortcut ⌘⌥T ──────────────────────────────────────────────────

    func setupGlobalShortcut() {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false]
            AXIsProcessTrustedWithOptions(opts)
            return
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmdOpt   : NSEvent.ModifierFlags = [.command, .option]

            switch (flags, event.keyCode) {
            case (cmdOpt,   17): StudyTimer.shared.toggle()                    // ⌘⌥T — start/pause
            case (cmdOpt,    3): self.finishSession()                           // ⌘⌥F — finish session
            case (cmdOpt,   15): StudyTimer.shared.reset()                     // ⌘⌥R — reset
            case (cmdOpt,    1): AnalyticsWindowController.show()              // ⌘⌥S — analytics
            case (cmdOpt,    2): TodayWindowController.show()                 // ⌘⌥D — today
            case (cmdOpt,    8): AIChatWindowController.show()                 // ⌘⌥C — AI chat
            case (cmdOpt,   35): StudyPlanWindowController.show()              // ⌘⌥P — study plan
            case (cmdOpt,   46): SessionEndWindowController.presentManual()    // ⌘⌥M — manual log
            case (cmdOpt,   37): self.logCurrentApp()                          // ⌘⌥L — log frontmost app
            case (cmdOpt,   40): StudyPlanWindowController.showTasks()         // ⌘⌥K — tasks
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
