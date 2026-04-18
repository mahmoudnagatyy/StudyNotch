import SwiftUI
import AppKit

// ── Subject Settings (Color + Telegram) ──────────────────────────────────────

struct SubjectSettingsView: View {
    var store    = SubjectStore.shared
    @Bindable var sessions = SessionStore.shared
    @Bindable var modeStore = ModeStore.shared
    var subjects: [String] {
        var s = sessions.knownSubjects
        if modeStore.currentMode == .college {
            let extra = modeStore.collegeSubjects.map(\.name)
            for e in extra { if !s.contains(e) { s.append(e) } }
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Subject Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            Divider().overlay(Color.white.opacity(0.07))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Global Telegram (one bot for all subjects) ────────────
                    GlobalTelegramSetup()
                        .padding(.horizontal, 20).padding(.vertical, 14)

                    Divider().overlay(Color.white.opacity(0.07))
                    
                    // ── Auto-Session Detection Settings ───────────────────────
                    AutoSessionSettingsSection()
                        .padding(.horizontal, 20).padding(.vertical, 14)

                    Divider().overlay(Color.white.opacity(0.07))

                    // ── Per-subject color + optional override ─────────────────
                    if subjects.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 28)).foregroundColor(.white.opacity(0.15))
                            Text("No subjects yet — start a study session first")
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.25))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else {
                        ForEach(subjects, id: \.self) { sub in
                            SubjectSettingsRow(subject: sub)
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color.black)
        .onAppear {
            for s in subjects { store.ensureMeta(for: s) }
        }
    }
}

// ── Subject Settings Row (color picker + per-subject Telegram override) ─────────

struct SubjectSettingsRow: View {
    @Bindable var store = SubjectStore.shared
    let subject: String

    @State private var meta: SubjectMeta = SubjectMeta(name: "")
    @State private var showOverride = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Color dot
                Circle()
                    .fill(store.color(for: subject))
                    .frame(width: 12, height: 12)
                    .shadow(color: store.color(for: subject).opacity(0.8), radius: 4)

                Text(subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 120, alignment: .leading)

                // Color palette
                HStack(spacing: 6) {
                    ForEach(0..<subjectPalette.count, id: \.self) { idx in
                        Button {
                            meta.colorIndex = idx
                            store.updateMeta(meta)
                        } label: {
                            ZStack {
                                Circle().fill(subjectPalette[idx]).frame(width: 16, height: 16)
                                if meta.colorIndex == idx {
                                    Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 16, height: 16)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Per-subject Telegram override toggle (only needed if not using global)
                if !store.useGlobalTelegram {
                    Button {
                        withAnimation { showOverride.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill").font(.system(size: 10))
                            Text("Override").font(.system(size: 11))
                            Image(systemName: showOverride ? "chevron.up" : "chevron.down").font(.system(size: 8))
                        }
                        .foregroundColor(
                            (meta.telegramBotToken.isEmpty || meta.telegramChatID.isEmpty)
                                ? .white.opacity(0.35)
                                : Color(red: 0.25, green: 0.72, blue: 1.0)
                        )
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.06)).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if showOverride && !store.useGlobalTelegram {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-subject Telegram bot for \(subject)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bot Token").font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                            TextField("1234567890:ABC...", text: $meta.telegramBotToken)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Chat ID").font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                            TextField("-100123456", text: $meta.telegramChatID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 110)
                        }
                        Button("Save") { store.updateMeta(meta) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.5))
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            meta = store.metas.first { $0.name == subject } ?? SubjectMeta(name: subject)
        }
        .onChange(of: store.metas) { _, metas in
            if let m = store.metas.first(where: { $0.name == subject }) { meta = m }
        }
    }
}

// ── Telegram Quick Note Field (shown in notch while session is running) ────────

struct TelegramQuickNoteField: View {
    var subStore     = SubjectStore.shared
    @Bindable var sessionStore = SessionStore.shared
    var timer        = StudyTimer.shared

    @State private var text        = ""
    @State private var feedback    = ""
    @State private var pastedImage : NSImage? = nil
    @FocusState private var focused: Bool

    var hasTelegram: Bool { subStore.hasTelegram(for: timer.currentSubject) }
    var canAct: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || pastedImage != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 5) {
                // Pasted image preview
                if let img = pastedImage {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 12).padding(.top, 6)
                        Button {
                            pastedImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.7))
                                .background(Color.black.opacity(0.5), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14).padding(.top, 8)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                    TextField("Quick note… (⌘V to paste image)", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                        .focused($focused)
                        .onSubmit { saveLocally() }
                        .onAppear {
                            // Monitor ⌘V for image paste
                            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                                if event.modifierFlags.contains(.command),
                                   event.charactersIgnoringModifiers == "v",
                                   self.focused {
                                    self.checkClipboardForImage()
                                }
                                return event
                            }
                        }
                }
                .padding(.horizontal, 12).padding(.top, 7)

                HStack(spacing: 6) {
                    Button { saveLocally() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down").font(.system(size: 9, weight: .semibold))
                            Text("Save").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(canAct ? .white.opacity(0.75) : .white.opacity(0.2))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(canAct ? Color.white.opacity(0.1) : Color.clear)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(!canAct)

                    if hasTelegram {
                        Button { sendToTelegram() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "paperplane.fill").font(.system(size: 9, weight: .semibold))
                                Text("Send").font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(canAct ? Color(red:0.25,green:0.72,blue:1) : .white.opacity(0.2))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(canAct ? Color(red:0.25,green:0.72,blue:1).opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain).disabled(!canAct)
                    } else {
                        Button { SubjectSettingsWindowController.show() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "paperplane").font(.system(size: 9))
                                Text("Set up Telegram").font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.2))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if !feedback.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundColor(.green)
                            Text(feedback).font(.system(size: 9)).foregroundColor(.green.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 6)
            }
        }
    }

    func checkClipboardForImage() {
        let pb = NSPasteboard.general
        if pb.canReadItem(withDataConformingToTypes: NSImage.imageTypes) {
            if let img = NSImage(pasteboard: pb) {
                withAnimation { pastedImage = img }
            }
        }
    }

    func saveLocally() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false || pastedImage != nil else { return }
        let subject = timer.currentSubject.isEmpty ? "General" : timer.currentSubject
        var note = QuickNote(subject: subject, text: trimmed)
        if let img = pastedImage {
            note.imageData = img.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        }
        sessionStore.saveQuickNote(note)
        // Also push to Notion notes database
        NotionService.shared.pushQuickNote(note) { _ in }
        showFeedback(pastedImage != nil ? "Saved with image" : "Saved")
        pastedImage = nil
    }

    func sendToTelegram() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard hasTelegram else { return }
        let subject = timer.currentSubject.isEmpty ? "General" : timer.currentSubject
        var note = QuickNote(subject: subject, text: trimmed, sentToTelegram: true)
        if let img = pastedImage {
            note.imageData = img.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
            // Send image to Telegram via sendPhoto
            if !trimmed.isEmpty {
                subStore.sendToTelegram(subject: subject, message: trimmed)
            }
            subStore.sendPhotoToTelegram(subject: subject, image: img, caption: trimmed)
        } else if !trimmed.isEmpty {
            subStore.sendToTelegram(subject: subject, message: trimmed)
        }
        sessionStore.saveQuickNote(note)
        NotionService.shared.pushQuickNote(note) { _ in }
        showFeedback("Sent ✈")
        pastedImage = nil
    }

    func showFeedback(_ msg: String) {
        withAnimation { feedback = msg; text = "" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { feedback = "" }
        }
    }
}

// ── Telegram Wizard ──────────────────────────────────────────────────────────
//
//  Fully automated setup:
//  Step 1 — Paste bot token → app auto-fetches chat ID via getUpdates polling
//  Step 2 — Auto-creates one Forum Topic per subject via createForumTopic API
//  Each subject gets its own thread in one Telegram supergroup.
//
//  How to prepare the Telegram side (one-time, ~2 min):
//  a) Message @BotFather → /newbot → copy token
//  b) Create a NEW Telegram group (any name, e.g. "StudyNotch")
//  c) In group Settings → Edit → Enable "Topics" (make it a Forum)
//  d) Add your bot to the group as Admin with "Manage Topics" permission
//  e) Send any message in the group
//  Then paste the token here — the wizard does the rest.

enum WizardStep { case token, fetchingID, topics, done, error(String) }

struct GlobalTelegramSetup: View {
    var store    = SubjectStore.shared
    @Bindable var sessions = SessionStore.shared
    @Bindable var modeStore = ModeStore.shared
    @State private var tokenInput   = ""
    @State private var step         : WizardStep = .token
    @State private var detectedChatID = ""
    @State private var topicProgress : [String: TopicState] = [:]
    @State private var showInstructions = false

    enum TopicState { case pending, creating, done(Int), failed(String) }

    // Diagnostic result from checkGroupRequirements
    struct DiagResult {
        var isSupergroup   : Bool = false
        var isForum        : Bool = false
        var botIsAdmin     : Bool = false
        var canManageTopics: Bool = false
        var error          : String? = nil
        var rawChat        : String = ""
        var rawAdmins      : String = ""

        var allGood: Bool { isSupergroup && isForum && botIsAdmin && canManageTopics }
    }

    @State private var diagResult: DiagResult? = nil
    @State private var isChecking  = false
    @State private var showRawChat  = false
    @State private var showRawAdmins = false

    var subjects: [String] {
        var s = sessions.knownSubjects
        if modeStore.currentMode == .college {
            let extra = modeStore.collegeSubjects.map(\.name)
            for e in extra { if !s.contains(e) { s.append(e) } }
        }
        return s
    }

    var isConfigured: Bool {
        !store.globalTelegramToken.isEmpty && !store.globalTelegramChatID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(isConfigured ? Color(red:0.25,green:0.72,blue:1) : .white.opacity(0.4))
                Text("Telegram Auto-Setup")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.9))
                Spacer()
                if isConfigured {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Connected").font(.system(size: 11)).foregroundColor(.green.opacity(0.8))
                    }
                    Button("Reset") { resetWizard() }
                        .buttonStyle(.plain).font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.6))
                }
            }

            // ── Instructions (collapsible) ────────────────────────────────────
            DisclosureGroup(isExpanded: $showInstructions) {
                VStack(alignment: .leading, spacing: 5) {
                    instructionRow("a", "@BotFather → /newbot → copy the token")
                    instructionRow("b", "Create a Telegram group (e.g. \"StudyNotch Notes\")")
                    instructionRow("c", "Group Settings → Edit → turn on Topics")
                    instructionRow("d", "Add your bot as Admin with \"Manage Topics\" permission")
                    instructionRow("e", "Send any message in the group, then come back here")
                    Text("The wizard will auto-detect the group and create one topic per subject.")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                        .padding(.top, 2)
                }
                .padding(.top, 6)
            } label: {
                Text(showInstructions ? "Hide setup instructions" : "▸ How to prepare Telegram (one-time, ~2 min)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }

            Divider().overlay(Color.white.opacity(0.08))

            // ── Wizard steps ──────────────────────────────────────────────────
            Group {
                if case .token = step {
                    tokenStep
                } else if case .fetchingID = step {
                    HStack(spacing: 10) {
                        ProgressView().scaleEffect(0.7)
                        Text("Waiting for a message in your group…")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        Button("Cancel") { step = .token }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.red.opacity(0.5))
                    }
                } else if case .topics = step {
                    topicsStep
                } else if case .done = step {
                    doneStep
                } else if case .error(let msg) = step {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(msg).font(.system(size: 11)).foregroundColor(.orange)
                        Button("Retry") { step = .token }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            tokenInput = store.globalTelegramToken
            if isConfigured {
                step = .done
                // Restore topic progress display from saved metas
                for sub in subjects {
                    if let meta = store.metas.first(where: { $0.name == sub }),
                       meta.telegramTopicID > 0 {
                        topicProgress[sub] = .done(meta.telegramTopicID)
                    }
                }
                detectedChatID = store.globalTelegramChatID
            }
        }
    }

    // ── Step 1: Token entry ───────────────────────────────────────────────────

    var tokenStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step 1 — Paste your bot token")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))

            HStack(spacing: 8) {
                TextField("1234567890:ABCdefGHIjklMNOpqrSTUvwx...", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                Button("Detect Chat →") {
                    guard !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.globalTelegramToken = tokenInput.trimmingCharacters(in: .whitespaces)
                    startFetchingChatID()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(red:0.25,green:0.72,blue:1))
                .clipShape(Capsule())
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("After clicking, send any message in your Telegram group. The app will auto-detect it.")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
        }
    }

    // ── Step 2: Diagnose + create topics ─────────────────────────────────────

    var topicsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chat detected banner
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 11))
                Text("Group detected: \(detectedChatID)")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }

            // ── Diagnostic panel ──────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Group requirements")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Button(isChecking ? "Checking…" : "Check Now") {
                        runDiagnostics()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red:0.25,green:0.72,blue:1))
                    .disabled(isChecking)
                }

                if let d = diagResult {
                    VStack(alignment: .leading, spacing: 4) {
                        diagRow("Is supergroup",         d.isSupergroup,
                                fix: "Telegram → tap group name → Edit → if you see 'Topics' option it's a supergroup. If not: make group public temporarily (set a username), save, then set back to private — this forces supergroup upgrade.")
                        diagRow("Topics enabled",        d.isForum,
                                fix: "Tap group name → Edit → scroll to bottom → toggle Topics ON → Save")
                        diagRow("Bot is admin",          d.botIsAdmin,
                                fix: "Tap group name → Members → Add Admin → find your bot and add it")
                        diagRow("Bot can manage topics", d.canManageTopics,
                                fix: "Tap group name → Administrators → tap your bot → make sure 'Manage topics' is toggled ON → Save")
                    }

                    if let err = d.error {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 10))
                            Text(err).font(.system(size: 10)).foregroundColor(.orange)
                        }
                    }

                    if d.allGood {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("All requirements met — ready to create topics!")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                        }
                    }

                    // Raw API response viewer — helps diagnose what Telegram actually returned
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            showRawChat.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showRawChat ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8))
                                Text("Show raw getChat response")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)

                        if showRawChat && !d.rawChat.isEmpty {
                            ScrollView {
                                Text(d.rawChat)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 80)
                            .padding(6)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Button {
                            showRawAdmins.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showRawAdmins ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8))
                                Text("Show raw getChatAdministrators response")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)

                        if showRawAdmins && !d.rawAdmins.isEmpty {
                            ScrollView {
                                Text(d.rawAdmins)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                            .padding(6)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text("Tap 'Check Now' to verify your group is set up correctly.")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // ── Subject list ──────────────────────────────────────────────────
            if !subjects.isEmpty {
                VStack(spacing: 4) {
                    ForEach(subjects, id: \.self) { sub in
                        topicRow(subject: sub)
                    }
                }

                // Action buttons
                HStack(spacing: 10) {
                    Button("Create All Topics →") {
                        createAllTopics()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(diagResult?.allGood == true
                        ? Color(red:0.25,green:0.72,blue:1)
                        : Color(red:0.25,green:0.72,blue:1).opacity(0.5))
                    .clipShape(Capsule())

                    Button("Retry Failed") {
                        retryFailed()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.8))
                    .opacity(topicProgress.values.contains { if case .failed = $0 { return true }; return false } ? 1 : 0)

                    Button("Skip — use main chat") {
                        store.globalTelegramChatID = detectedChatID
                        store.useGlobalTelegram    = true
                        store.saveGlobalTelegram()
                        step = .done
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.35))
                }
            } else {
                Text("No subjects yet — start a study session first.")
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    func diagRow(_ label: String, _ ok: Bool, fix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(ok ? .green : .red)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(ok ? .white.opacity(0.7) : .white.opacity(0.9))
            }
            if !ok {
                Text("Fix: \(fix)")
                    .font(.system(size: 9))
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(.leading, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func topicRow(subject: String) -> some View {
        let state = topicProgress[subject]
        return HStack(spacing: 8) {
            Circle().fill(store.color(for: subject)).frame(width: 7, height: 7)
            Text(subject)
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Group {
                if let s = state {
                    if case .creating = s {
                        ProgressView().scaleEffect(0.6)
                    } else if case .done(let id) = s {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.system(size: 10))
                            Text("topic #\(id)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.green.opacity(0.7))
                        }
                    } else if case .failed(let reason) = s {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red).font(.system(size: 10))
                            Text(reason.isEmpty ? "failed" : reason)
                                .font(.system(size: 9))
                                .foregroundColor(.red.opacity(0.8))
                                .lineLimit(1)
                        }
                    } else {
                        Text("–").font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
                    }
                } else {
                    Text("–").font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
                }
            }
        }
        .padding(.vertical, 3)
    }

    // ── Step 3: Done ──────────────────────────────────────────────────────────

    var doneStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 14))
                Text("Telegram connected")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Button("Reset") { resetWizard() }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.red.opacity(0.5))
            }

            // Per-subject topic status — read from persisted meta, not topicProgress
            VStack(spacing: 3) {
                ForEach(subjects, id: \.self) { sub in
                    let topicID = store.metas.first { $0.name == sub }?.telegramTopicID ?? 0
                    HStack(spacing: 8) {
                        Circle().fill(store.color(for: sub)).frame(width: 7, height: 7)
                        Text(sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
                        Spacer()
                        if topicID > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green).font(.system(size: 10))
                                Text("topic #\(topicID)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.7))
                            }
                        } else {
                            Text("no topic — uses main chat")
                                .font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Actions
            HStack(spacing: 8) {
                // Test a single subject
                Button("Test →") {
                    if let first = subjects.first {
                        store.sendToTelegram(subject: first, message: "🔔 Test — \(first) topic works!")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(red:0.25,green:0.72,blue:1))
                .clipShape(Capsule())

                Button("Test All") {
                    for sub in subjects {
                        store.sendToTelegram(subject: sub, message: "🔔 Test from StudyNotch — \(sub)")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                Button("Create Missing Topics") {
                    let missing = subjects.filter { sub in
                        !(store.metas.first(where: { $0.name == sub })?.telegramTopicID ?? 0 > 0)
                    }
                    if !missing.isEmpty {
                        for sub in missing { topicProgress[sub] = .pending }
                        createTopicSequentially(subjects: missing,
                                                token: store.globalTelegramToken,
                                                chatID: store.globalTelegramChatID,
                                                index: 0)
                        step = .topics
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))

                Spacer()
            }

            Text("Chat ID: \(store.globalTelegramChatID)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    func startFetchingChatID() {
        step = .fetchingID
        pollForChatID(attempts: 20)
    }

    func pollForChatID(attempts: Int) {
        guard attempts > 0 else {
            step = .error("No message received. Send any message in your group, then retry.")
            return
        }
        store.fetchChatID(token: store.globalTelegramToken) { chatID in
            if let id = chatID {
                detectedChatID = id
                store.globalTelegramChatID = id
                store.useGlobalTelegram    = true
                store.saveGlobalTelegram()
                // Init topic states
                for sub in subjects { topicProgress[sub] = .pending }
                step = .topics
            } else {
                // Poll again after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    pollForChatID(attempts: attempts - 1)
                }
            }
        }
    }

    func createAllTopics() {
        let token  = store.globalTelegramToken
        let chatID = store.globalTelegramChatID
        guard !token.isEmpty, !chatID.isEmpty else { return }

        // Create topics sequentially to avoid rate limiting
        createTopicSequentially(subjects: subjects, token: token, chatID: chatID, index: 0)
    }

    func createTopicSequentially(subjects: [String], token: String, chatID: String, index: Int) {
        guard index < subjects.count else {
            // All done — check if any succeeded
            let anyDone = topicProgress.values.contains { if case .done = $0 { return true }; return false }
            step = anyDone ? .done : .error("All topics failed. Check requirements above and retry.")
            return
        }
        let sub = subjects[index]
        topicProgress[sub] = .creating

        store.createForumTopic(token: token, chatID: chatID, name: "📚 \(sub)") { topicID, errorMsg in
            if let tid = topicID {
                topicProgress[sub] = .done(tid)
                store.setTopicID(tid, for: sub)
            } else {
                let reason = errorMsg ?? "unknown"
                topicProgress[sub] = .failed(reason)
            }
            // 1 second between requests — Telegram rate limits forum topic creation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                createTopicSequentially(subjects: subjects, token: token, chatID: chatID, index: index + 1)
            }
        }
    }

    func retryFailed() {
        let failed = subjects.filter {
            if case .failed = topicProgress[$0] { return true }
            return false
        }
        guard !failed.isEmpty else { return }
        let token  = store.globalTelegramToken
        let chatID = store.globalTelegramChatID
        createTopicSequentially(subjects: failed, token: token, chatID: chatID, index: 0)
    }

    func runDiagnostics() {
        isChecking   = true
        diagResult   = nil
        showRawChat  = false
        showRawAdmins = false
        store.checkGroupRequirements(
            token: store.globalTelegramToken,
            chatID: store.globalTelegramChatID
        ) { isSupergroup, isForum, botIsAdmin, canManageTopics, error, rawChat, rawAdmins in
            isChecking = false
            diagResult = DiagResult(
                isSupergroup: isSupergroup,
                isForum: isForum,
                botIsAdmin: botIsAdmin,
                canManageTopics: canManageTopics,
                error: error,
                rawChat: rawChat,
                rawAdmins: rawAdmins
            )
        }
    }

    func resetWizard() {
        store.globalTelegramToken  = ""
        store.globalTelegramChatID = ""
        store.useGlobalTelegram    = true
        store.saveGlobalTelegram()
        // Clear topic IDs
        for i in store.metas.indices {
            store.metas[i].telegramTopicID = 0
        }
        tokenInput    = ""
        topicProgress = [:]
        step = .token
    }

    func instructionRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red:0.25,green:0.72,blue:1))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// ── Window Controller ─────────────────────────────────────────────────────────

class SubjectSettingsWindowController: NSWindowController {
    static var shared: SubjectSettingsWindowController?

    static func show() {
        if shared == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            win.title = "Subject Settings"
            win.isReleasedWhenClosed = false
            win.minSize = NSSize(width: 480, height: 400)
            win.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            win.contentView = NSHostingView(rootView: SubjectSettingsView())
            win.center()
            shared = SubjectSettingsWindowController(window: win)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
                shared = nil
            }
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }
}

// ── Auto-Session Detection Settings ──────────────────────────────────────────

struct AutoSessionSettingsSection: View {
    @Bindable var detector = AutoSessionDetector.shared
    @State private var newIgnoreInput = ""
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Apps or folders in this list will never trigger auto-session suggestions.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    TextField("App name, bundle ID, or path...", text: $newIgnoreInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    
                    Button("Add") {
                        let trimmed = newIgnoreInput.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !detector.ignoreList.contains(trimmed) else { return }
                        var list = detector.ignoreList
                        list.append(trimmed)
                        detector.ignoreList = list
                        newIgnoreInput = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .disabled(newIgnoreInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if detector.ignoreList.isEmpty {
                    Text("No ignored items yet.")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.2))
                        .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detector.ignoreList, id: \.self) { item in
                            HStack {
                                Text(item).font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Button {
                                    detector.ignoreList.removeAll { $0 == item }
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash.fill").foregroundColor(.orange)
                Text("Auto-Detect Ignore List")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.9))
                Spacer()
                Text("\(detector.ignoreList.count) items")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
            }
        }
    }
}
