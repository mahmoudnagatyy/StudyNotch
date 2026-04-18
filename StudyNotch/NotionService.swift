import Foundation
import Observation
import AppKit

// ── Notion Service ────────────────────────────────────────────────────────────
//
//  Structure on Notion (auto-created on first use):
//
//  📚 StudyNotch  ← root page (you paste its ID into the app)
//  ├── Math        ← one page per subject
//  │   ├── [Sessions database]   — one row per session
//  │   └── [Notes database]      — one row per quick note
//  ├── Physics
//  │   ├── [Sessions database]
//  │   └── [Notes database]
//  └── ...
//
//  Setup: notion.so/my-integrations → create integration → paste key in app
//  Share the root page with the integration (Share → Invite → your integration)

@Observable
final class NotionService {
    static let shared = NotionService()

    // ── Published state ───────────────────────────────────────────────────────
     var isConnected   : Bool   = false
     var lastError     : String = ""
     var isSyncing     : Bool   = false
     var status        : String = "Not connected"

    // ── Persisted config ──────────────────────────────────────────────────────
    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "notion.apiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notion.apiKey")
              isConnected = !newValue.isEmpty
              status = isConnected ? "Connected" : "Not connected" }
    }
    var rootPageID: String {
        get { UserDefaults.standard.string(forKey: "notion.rootPageID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "notion.rootPageID") }
    }

    // Cache: subject name → { sessionDBID, notesDBID, pageID }
    private var subjectCache: [String: SubjectPages] = {
        guard let data = UserDefaults.standard.data(forKey: "notion.subjectCache"),
              let map  = try? JSONDecoder().decode([String: SubjectPages].self, from: data)
        else { return [:] }
        return map
    }()

    private struct SubjectPages: Codable {
        var pageID       : String
        var sessionDBID  : String
        var notesDBID    : String
    }

    private let base    = "https://api.notion.com/v1"
    private let version = "2022-06-28"

    init() {
        isConnected = !apiKey.isEmpty
        if isConnected { status = "Connected" }
    }

    // ── Public entry points ───────────────────────────────────────────────────

    /// Push a study session to the subject's Sessions database
    func pushSession(_ session: StudySession, completion: @escaping (Bool) -> Void) {
        guard isConnected else { completion(false); return }
        getOrCreateSubjectPages(subject: session.subject) { pages in
            guard let pages = pages else { completion(false); return }
            self.createSessionRow(session: session, databaseID: pages.sessionDBID, completion: completion)
        }
    }

    /// Push a quick note (with optional image) to the subject's Notes database
    func pushQuickNote(_ note: QuickNote, completion: @escaping (Bool) -> Void) {
        guard isConnected else { completion(false); return }
        let subject = note.subject.isEmpty ? "General" : note.subject
        getOrCreateSubjectPages(subject: subject) { pages in
            guard let pages = pages else { completion(false); return }
            self.createNoteRow(note: note, databaseID: pages.notesDBID, completion: completion)
        }
    }

    /// Test the connection — verify API key works
    func testConnection(completion: @escaping (Bool, String) -> Void) {
        guard !apiKey.isEmpty else {
            completion(false, "No API key set"); return
        }
        request(method: "GET", path: "/users/me", body: nil) { data, code in
            if code == 200 {
                let name = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
                    .flatMap { ($0["name"] as? String) } ?? "Connected"
                DispatchQueue.main.async { completion(true, "✓ Connected as \(name)") }
            } else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                DispatchQueue.main.async { completion(false, "[\(code)] \(msg.prefix(120))") }
            }
        }
    }

    // ── Subject page management ───────────────────────────────────────────────

    private func getOrCreateSubjectPages(subject: String, completion: @escaping (SubjectPages?) -> Void) {
        // Check cache first
        if let cached = subjectCache[subject] {
            completion(cached); return
        }
        // Need root page ID
        guard !rootPageID.isEmpty else {
            DispatchQueue.main.async {
                self.lastError = "Root page ID not set — paste it in Notion settings"
                completion(nil)
            }
            return
        }
        // Search for existing subject page
        searchForPage(title: subject) { existingID in
            if let pid = existingID {
                // Page exists — find or create its databases
                self.getOrCreateDatabases(pageID: pid, subject: subject, completion: completion)
            } else {
                // Create subject page
                self.createSubjectPage(title: subject) { pageID in
                    guard let pid = pageID else { completion(nil); return }
                    self.getOrCreateDatabases(pageID: pid, subject: subject, completion: completion)
                }
            }
        }
    }

    private func searchForPage(title: String, completion: @escaping (String?) -> Void) {
        let body: [String: Any] = [
            "query": title,
            "filter": ["property": "object", "value": "page"]
        ]
        request(method: "POST", path: "/search", body: body) { data, code in
            guard code == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]]
            else { DispatchQueue.main.async { completion(nil) }; return }

            // Find a page whose title matches exactly and is under our root page
            for r in results {
                guard let id     = r["id"] as? String,
                      let parent = r["parent"] as? [String: Any],
                      let props  = r["properties"] as? [String: Any],
                      let titleProp = props["title"] as? [String: Any],
                      let titleArr  = titleProp["title"] as? [[String: Any]],
                      let text      = titleArr.first?["plain_text"] as? String,
                      text.lowercased() == title.lowercased()
                else { continue }

                // Verify parent is our root page
                let parentID = (parent["page_id"] as? String) ?? ""
                if parentID.replacingOccurrences(of: "-", with: "") ==
                   self.rootPageID.replacingOccurrences(of: "-", with: "") {
                    DispatchQueue.main.async { completion(id) }
                    return
                }
            }
            DispatchQueue.main.async { completion(nil) }
        }
    }

    private func createSubjectPage(title: String, completion: @escaping (String?) -> Void) {
        let emoji = subjectEmoji(title)
        let body: [String: Any] = [
            "parent": ["page_id": rootPageID],
            "icon"  : ["type": "emoji", "emoji": emoji],
            "properties": [
                "title": [
                    "title": [["type": "text", "text": ["content": title]]]
                ]
            ],
            "children": [
                headingBlock("📋 Sessions", level: 2),
                dividerBlock(),
                headingBlock("📝 Quick Notes", level: 2),
                dividerBlock()
            ]
        ]
        request(method: "POST", path: "/pages", body: body) { data, code in
            guard (code == 200 || code == 201),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id   = json["id"] as? String
            else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
                print("[Notion] createSubjectPage failed \(code): \(msg.prefix(200))")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(id) }
        }
    }

    private func getOrCreateDatabases(pageID: String, subject: String, completion: @escaping (SubjectPages?) -> Void) {
        // Create both databases in sequence
        createSessionsDatabase(pageID: pageID, subject: subject) { sessDBID in
            guard let sessDBID = sessDBID else { completion(nil); return }
            self.createNotesDatabase(pageID: pageID, subject: subject) { notesDBID in
                guard let notesDBID = notesDBID else { completion(nil); return }
                let pages = SubjectPages(pageID: pageID, sessionDBID: sessDBID, notesDBID: notesDBID)
                DispatchQueue.main.async {
                    self.subjectCache[subject] = pages
                    if let data = try? JSONEncoder().encode(self.subjectCache) {
                        UserDefaults.standard.set(data, forKey: "notion.subjectCache")
                    }
                    completion(pages)
                }
            }
        }
    }

    // ── Database creation ─────────────────────────────────────────────────────

    private func createSessionsDatabase(pageID: String, subject: String, completion: @escaping (String?) -> Void) {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": pageID],
            "icon"  : ["type": "emoji", "emoji": "📋"],
            "title" : [["type": "text", "text": ["content": "\(subject) — Sessions"]]],
            "properties": [
                "Session"    : ["title": [:]],
                "Date"       : ["date": [:]],
                "Duration"   : ["rich_text": [:]],
                "Difficulty" : ["select": ["options": [
                    ["name": "⭐ Hard",       "color": "red"],
                    ["name": "⭐⭐",          "color": "orange"],
                    ["name": "⭐⭐⭐ OK",    "color": "yellow"],
                    ["name": "⭐⭐⭐⭐",     "color": "green"],
                    ["name": "⭐⭐⭐⭐⭐ Easy", "color": "blue"],
                ]]],
                "Distractions": ["number": ["format": "number"]],
                "Type"       : ["select": ["options": [
                    ["name": "Live",   "color": "green"],
                    ["name": "Manual", "color": "gray"],
                ]]],
                "Notes"      : ["rich_text": [:]],
            ]
        ]
        request(method: "POST", path: "/databases", body: body) { data, code in
            guard (code == 200 || code == 201),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id   = json["id"] as? String
            else { DispatchQueue.main.async { completion(nil) }; return }
            DispatchQueue.main.async { completion(id) }
        }
    }

    private func createNotesDatabase(pageID: String, subject: String, completion: @escaping (String?) -> Void) {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": pageID],
            "icon"  : ["type": "emoji", "emoji": "📝"],
            "title" : [["type": "text", "text": ["content": "\(subject) — Notes"]]],
            "properties": [
                "Note"          : ["title": [:]],
                "Date"          : ["date": [:]],
                "Sent to Telegram": ["checkbox": [:]],
                "Has Image"     : ["checkbox": [:]],
            ]
        ]
        request(method: "POST", path: "/databases", body: body) { data, code in
            guard (code == 200 || code == 201),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id   = json["id"] as? String
            else { DispatchQueue.main.async { completion(nil) }; return }
            DispatchQueue.main.async { completion(id) }
        }
    }

    // ── Row creation ──────────────────────────────────────────────────────────

    private func createSessionRow(session: StudySession, databaseID: String, completion: @escaping (Bool) -> Void) {
        let h   = Int(session.duration) / 3600
        let m   = (Int(session.duration) % 3600) / 60
        let dur = h > 0 ? "\(h)h \(m)m" : "\(m)m"

        let diffLabels = ["", "⭐ Hard", "⭐⭐", "⭐⭐⭐ OK", "⭐⭐⭐⭐", "⭐⭐⭐⭐⭐ Easy"]
        let diff = session.difficulty > 0 ? diffLabels[min(session.difficulty, 5)] : "⭐⭐⭐ OK"

        let iso = ISO8601DateFormatter()

        var props: [String: Any] = [
            "Session"    : ["title": [["type": "text", "text": ["content": session.subject + " — " + dur]]]],
            "Date"       : ["date": ["start": iso.string(from: session.startTime)]],
            "Duration"   : ["rich_text": [["type": "text", "text": ["content": dur]]]],
            "Difficulty" : ["select": ["name": diff]],
            "Distractions": ["number": session.distractions.count],
            "Type"       : ["select": ["name": session.isManual ? "Manual" : "Live"]],
        ]
        if !session.notes.trimmingCharacters(in: .whitespaces).isEmpty {
            props["Notes"] = ["rich_text": [["type": "text", "text": ["content": session.notes]]]]
        }

        let body: [String: Any] = [
            "parent"    : ["database_id": databaseID],
            "properties": props
        ]
        request(method: "POST", path: "/pages", body: body) { _, code in
            DispatchQueue.main.async { completion(code == 200 || code == 201) }
        }
    }

    private func createNoteRow(note: QuickNote, databaseID: String, completion: @escaping (Bool) -> Void) {
        let iso = ISO8601DateFormatter()
        let text = note.text.trimmingCharacters(in: .whitespaces)
        let title = text.isEmpty ? "(image)" : String(text.prefix(80))
        let hasImage = note.imageData != nil

        let props: [String: Any] = [
            "Note"            : ["title": [["type": "text", "text": ["content": title]]]],
            "Date"            : ["date": ["start": iso.string(from: note.date)]],
            "Sent to Telegram": ["checkbox": note.sentToTelegram],
            "Has Image"       : ["checkbox": hasImage],
        ]

        var children: [[String: Any]] = []

        // Add note text as a paragraph block
        if !text.isEmpty {
            children.append(paragraphBlock(text))
        }

        // Add image as a Notion image block (uploaded via external URL trick)
        // Notion doesn't support direct image upload via API for free plans.
        // So we embed it as a file block with base64 data URI — works in rich text
        if let imgData = note.imageData {
            let b64 = imgData.base64EncodedString()
            // Notion image blocks require a URL — we use a data URI for inline embedding
            // Note: This works for viewing in Notion apps but not in the web sidebar
            children.append([
                "object": "block",
                "type"  : "image",
                "image" : [
                    "type"    : "external",
                    "external": ["url": "data:image/png;base64," + b64]
                ]
            ] as [String: Any])
        }

        let body: [String: Any] = [
            "parent"    : ["database_id": databaseID],
            "properties": props,
            "children"  : children.isEmpty ? NSNull() : children
        ]

        // Clean up NSNull if no children
        var cleanBody = body
        if children.isEmpty { cleanBody.removeValue(forKey: "children") }

        request(method: "POST", path: "/pages", body: cleanBody) { _, code in
            DispatchQueue.main.async { completion(code == 200 || code == 201) }
        }
    }

    // ── Block helpers ─────────────────────────────────────────────────────────

    private func headingBlock(_ text: String, level: Int) -> [String: Any] {
        let type = "heading_\(level)"
        return [
            "object": "block",
            "type"  : type,
            type    : ["rich_text": [["type": "text", "text": ["content": text]]]]
        ]
    }

    private func dividerBlock() -> [String: Any] {
        return ["object": "block", "type": "divider", "divider": [:]]
    }

    private func paragraphBlock(_ text: String) -> [String: Any] {
        return [
            "object": "block",
            "type"  : "paragraph",
            "paragraph": ["rich_text": [["type": "text", "text": ["content": text]]]]
        ]
    }

    // ── Core HTTP ─────────────────────────────────────────────────────────────

    private func request(method: String, path: String, body: [String: Any]?, completion: @escaping (Data?, Int) -> Void) {
        guard let url = URL(string: base + path) else { completion(nil, 0); return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer " + apiKey,          forHTTPHeaderField: "Authorization")
        req.setValue("application/json",           forHTTPHeaderField: "Content-Type")
        req.setValue(version,                      forHTTPHeaderField: "Notion-Version")
        req.timeoutInterval = 30

        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 && code != 201 {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
                print("[Notion] \(method) \(path) → \(code): \(raw.prefix(200))")
                DispatchQueue.main.async { self.lastError = "[\(code)] \(raw.prefix(150))" }
            }
            completion(data, code)
        }.resume()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    func clearCache() {
        subjectCache = [:]
        UserDefaults.standard.removeObject(forKey: "notion.subjectCache")
    }

    private func subjectEmoji(_ subject: String) -> String {
        let s = subject.lowercased()
        if s.contains("math")    || s.contains("calc")   { return "📐" }
        if s.contains("physics") || s.contains("phys")   { return "⚡" }
        if s.contains("chem")                             { return "⚗️" }
        if s.contains("bio")                              { return "🧬" }
        if s.contains("cyber") || s.contains("security") { return "🔐" }
        if s.contains("network")                          { return "🌐" }
        if s.contains("data")  || s.contains("sql")      { return "🗄️" }
        if s.contains("ai")    || s.contains("machine")  { return "🤖" }
        if s.contains("prog")  || s.contains("code")     { return "💻" }
        if s.contains("english") || s.contains("lang")   { return "📖" }
        return "📚"
    }
}
