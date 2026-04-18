import SwiftUI
import AppKit

// ── AI Chat View ──────────────────────────────────────────────────────────────

struct AIChatView: View {
    @Bindable var chat = AIChatStore.shared
    var ai   = AIService.shared

    @State private var inputText    = ""
    @State private var showMemory   = false
    @State private var showClear    = false
    @FocusState private var focused : Bool

    private let accent = Color(red: 0.2, green: 1.0, blue: 0.55)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.white.opacity(0.07))

            if chat.messages.filter({ $0.role != .system }).isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider().overlay(Color.white.opacity(0.07))
            inputBar
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
    }

    // ── Toolbar ───────────────────────────────────────────────────────────────

    var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 15)).foregroundColor(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Study Coach").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Text("Remembers your study history & past chats")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }

            Spacer()

            // Memory toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showMemory.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill").font(.system(size: 11))
                    Text("Memory").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(showMemory ? .black : accent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(showMemory ? accent : accent.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Clear conversation
            Button {
                showClear = true
            } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Clear conversation?", isPresented: $showClear) {
                Button("Clear Chat History", role: .destructive) { chat.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // ── Memory panel ──────────────────────────────────────────────────────────

    var memoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bookmark.fill").foregroundColor(accent).font(.system(size: 11))
                Text("Pinned Memory").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button("Clear") { chat.clearMemory() }
                    .font(.system(size: 10)).foregroundColor(.red.opacity(0.7)).buttonStyle(.plain)
            }

            if chat.pinnedMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing remembered yet. Say \"remember that…\" to save facts.")
                    .font(.system(size: 11)).foregroundColor(.secondary).italic()
            } else {
                Text(chat.pinnedMemory)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("The AI uses this in every reply. It automatically grows when you say \"remember that…\"")
                .font(.system(size: 9)).foregroundColor(.secondary)
        }
        .padding(12)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.2), lineWidth: 0.5))
        .padding(.horizontal, 12).padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // ── Message list ──────────────────────────────────────────────────────────

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if showMemory { memoryPanel }

                    ForEach(chat.messages.filter { $0.role != .system }) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }

                    if chat.isTyping {
                        TypingIndicator()
                            .padding(.leading, 16).padding(.vertical, 6)
                            .id("typing")
                    }

                    // Invisible anchor for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.bottom, 8)
            }
            .onChange(of: chat.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: chat.isTyping) { typing in
                if typing { withAnimation { proxy.scrollTo("typing") } }
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────────

    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if showMemory { memoryPanel.padding(.horizontal, 4) }
            ZStack {
                Circle().fill(accent.opacity(0.1)).frame(width: 64, height: 64)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28)).foregroundColor(accent)
            }
            Text("AI Study Coach").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
            Text("Ask me anything about your studies.\nI know your subjects, tasks, exams, and session history.")
                .font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Suggested starters
            VStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        inputText = s
                        focused = true
                    } label: {
                        Text(s)
                            .font(.system(size: 11))
                            .foregroundColor(accent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(accent.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    let suggestions = [
        "What should I study today?",
        "How am I doing this week?",
        "Which subject needs the most attention?",
        "Give me a 3-day exam prep plan",
        "What are my biggest distraction patterns?"
    ]

    // ── Input bar ─────────────────────────────────────────────────────────────

    var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your study coach…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    // Cmd+Enter or Enter (without shift) sends
                    sendMessage()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(focused ? accent.opacity(0.4) : Color.clear, lineWidth: 1))

            Button(action: sendMessage) {
                Image(systemName: chat.isTyping ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty && !chat.isTyping
                                     ? .white.opacity(0.2) : accent)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty && !chat.isTyping)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chat.send(text)
    }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    private let accent = Color(red: 0.2, green: 1.0, blue: 0.55)
    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                // Bubble
                ZStack(alignment: .bottomTrailing) {
                    if isUser {
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(accent)
                            .clipShape(BubbleShape(isUser: true))
                    } else {
                        MarkdownText(message.content)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.07))
                            .clipShape(BubbleShape(isUser: false))
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.content, forType: .string)
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                                }
                            }
                    }
                }

                // Timestamp
                Text(timeFmt.string(from: message.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

// ── Bubble shape — chat-style rounded corners ─────────────────────────────────

struct BubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let tr: CGFloat = isUser ? 4 : r
        let tl: CGFloat = isUser ? r : 4
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// ── Typing indicator — three pulsing dots ────────────────────────────────────

struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    private let accent = Color(red: 0.2, green: 1.0, blue: 0.55)

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(accent.opacity(phase == i ? 1.0 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.2 : 0.9)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// ── Standalone Chat Window ────────────────────────────────────────────────────

class AIChatWindowController: NSWindowController {
    static var shared: AIChatWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "AI Study Coach"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.minSize = NSSize(width: 400, height: 500)
        win.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: AIChatView())
        let c = AIChatWindowController(window: win)
        shared = c
        c.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: win, queue: .main
        ) { _ in AIChatWindowController.shared = nil }
    }
}
