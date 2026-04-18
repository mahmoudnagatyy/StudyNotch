import Foundation
import Observation
import Combine
import SwiftUI
import Observation

// ── Chat Message ──────────────────────────────────────────────────────────────

struct ChatMessage: Codable, Identifiable, Equatable {
    var id        = UUID()
    var role      : ChatRole
    var content   : String
    var timestamp : Date = Date()

    enum ChatRole: String, Codable {
        case user, assistant, system
    }
}

// ── Chat Store — persistent multi-turn conversation + memory ──────────────────
//
//  Memory works in two layers:
//    1. Full conversation history (last N messages sent as context on every turn)
//    2. Pinned memory block — a system message injected at the top of every
//       request summarising things the AI should always remember about the user.
//       The AI itself can be asked to update this ("remember that…").
//
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class AIChatStore {
    static let shared = AIChatStore()

     var messages     : [ChatMessage] = []
     var pinnedMemory : String        = ""   // persisted user facts
     var isTyping     : Bool          = false

    // How many messages to include as rolling context (keeps tokens manageable)
    private let maxContextMessages = 20

    private var messagesURL : URL { dataDir().appendingPathComponent("chat_history.json") }
    private var memoryURL   : URL { dataDir().appendingPathComponent("chat_memory.txt") }

    private func dataDir() -> URL {
        let s = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = s.appendingPathComponent("StudyNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    init() { load() }

    // ── Send a user message and get a reply ───────────────────────────────────

    func send(_ text: String) {
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        saveMessages()
        isTyping = true

        AIService.shared.chat(
            history     : contextMessages(),
            systemPrompt: buildSystemPrompt()
        ) { [weak self] reply in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTyping = false
                let assistantMsg = ChatMessage(role: .assistant, content: reply)
                self.messages.append(assistantMsg)
                self.saveMessages()

                // Auto-extract memory updates from AI replies
                self.extractMemoryUpdates(from: reply)
            }
        }
    }

    // ── Build the system prompt ───────────────────────────────────────────────

    private func buildSystemPrompt() -> String {
        let store = SessionStore.shared

        var parts: [String] = []

        parts.append("""
        You are a smart, honest study coach embedded in StudyNotch — a macOS study timer app.
        You have full access to the student's study data and remember past conversations.
        Be concise, direct, and practical. Never repeat the question back. Use markdown formatting.
        When the user asks you to remember something, confirm you've noted it.
        """)

        // Pinned memory (user facts the AI should always know)
        if !pinnedMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("=== WHAT I KNOW ABOUT YOU ===\n\(pinnedMemory)")
        }

        // Live study context
        parts.append("=== YOUR CURRENT STUDY DATA ===\n\(store.fullContextForAI)")

        return parts.joined(separator: "\n\n")
    }

    // ── Rolling context window ────────────────────────────────────────────────

    private func contextMessages() -> [ChatMessage] {
        // Only user + assistant messages (not system) as rolling history
        let history = messages.filter { $0.role != .system }
        return Array(history.suffix(maxContextMessages))
    }

    // ── Memory extraction ─────────────────────────────────────────────────────
    // If the AI reply contains memory-worthy facts (prefixed "MEMORY:") update them.
    // The AI is instructed to emit these when the user says "remember that X".

    private func extractMemoryUpdates(from reply: String) {
        let lines = reply.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("MEMORY:") {
                let fact = trimmed.dropFirst("MEMORY:".count).trimmingCharacters(in: .whitespaces)
                appendMemory(fact)
            }
        }
    }

    func appendMemory(_ fact: String) {
        guard !fact.isEmpty else { return }
        let line = "• \(fact)"
        if !pinnedMemory.contains(line) {
            pinnedMemory += (pinnedMemory.isEmpty ? "" : "\n") + line
            saveMemory()
        }
    }

    func clearMemory() {
        pinnedMemory = ""
        saveMemory()
    }

    func clearHistory() {
        messages = []
        saveMessages()
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private func saveMessages() {
        // Keep only last 200 messages on disk
        let toSave = Array(messages.suffix(200))
        try? JSONEncoder().encode(toSave).write(to: messagesURL, options: .atomic)
    }

    private func saveMemory() {
        try? pinnedMemory.data(using: .utf8)?.write(to: memoryURL, options: .atomic)
    }

    private func load() {
        if let data    = try? Data(contentsOf: messagesURL),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = decoded
        }
        if let data = try? Data(contentsOf: memoryURL),
           let text = String(data: data, encoding: .utf8) {
            pinnedMemory = text
        }
    }
}
