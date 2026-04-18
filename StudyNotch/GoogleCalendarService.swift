import UserNotifications
import Foundation
import Observation
import AppKit

// ── Google Calendar Sync ──────────────────────────────────────────────────────
//
//  Uses Google Calendar API v3 with OAuth2 (installed-app flow).
//  No third-party dependencies — pure URLSession.
//
//  SETUP (one-time):
//  1. Go to console.cloud.google.com → New project → "StudyNotch"
//  2. APIs & Services → Enable → "Google Calendar API"
//  3. OAuth consent screen → External → add your email as test user
//  4. Credentials → Create → OAuth client ID → Desktop App
//  5. Download JSON → copy clientID and clientSecret below
//  6. In StudyNotch: Analytics → Settings → Google Calendar → Connect
//
// ─────────────────────────────────────────────────────────────────────────────

struct CalendarEvent: Identifiable {
    let id        = UUID()
    let title     : String
    let startTime : Date?

    var timeLabel: String {
        guard let t = startTime else { return "" }
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: t)
    }

    var isStudySession: Bool { title.hasPrefix("📚") }
    var subject: String {
        guard isStudySession else { return title }
        return title.replacingOccurrences(of: "📚 ", with: "")
    }
}

@Observable
final class GoogleCalendarService {
    static let shared = GoogleCalendarService()

    // ── OAuth credentials — fill these in after Google Cloud setup ───────────
    // Leave empty to show setup instructions in the UI
    private var clientID     = UserDefaults.standard.string(forKey: "gcal.clientID")     ?? ""
    private var clientSecret = UserDefaults.standard.string(forKey: "gcal.clientSecret") ?? ""

    // Stored tokens
     var isConnected: Bool = false
     var status: String    = "Not connected"
     var isSyncing: Bool   = false
     var lastSyncDate: Date?
     var lastError: String  = ""    // last API error — shown in UI

    private var accessToken : String = ""
    private var refreshToken: String = ""
    private var tokenExpiry : Date   = .distantPast

    // Which calendar to write to (nil = primary)
     var calendarID: String = "primary"

    // Auto-sync toggle
     var todayEvents    : [CalendarEvent] = []   // fetched at launch + hourly
     var autoSync: Bool = false {
        didSet { UserDefaults.standard.set(autoSync, forKey: "gcal.autoSync") }
    }

    private let redirectURI = "http://127.0.0.1:8080"
    private let scope       = "https://www.googleapis.com/auth/calendar.events"
    private let tokenURL    = URL(string: "https://oauth2.googleapis.com/token")!
    private let eventsURL   = "https://www.googleapis.com/calendar/v3/calendars"

    private var authServer: LocalAuthServer?

    init() {
        // Load saved tokens
        accessToken  = UserDefaults.standard.string(forKey: "gcal.accessToken")  ?? ""
        refreshToken = UserDefaults.standard.string(forKey: "gcal.refreshToken")  ?? ""
        autoSync     = UserDefaults.standard.bool(forKey: "gcal.autoSync")
        if let exp = UserDefaults.standard.object(forKey: "gcal.tokenExpiry") as? Date {
            tokenExpiry = exp
        }
        isConnected = !refreshToken.isEmpty
        if isConnected { status = "Connected" }
    }

    // ── OAuth flow ────────────────────────────────────────────────────────────

    /// Step 1 — open browser for user authorization
    func authenticate() {
        guard !clientID.isEmpty else {
            status = "Enter Client ID first"
            return
        }
        
        // Start local server to catch the callback
        authServer = LocalAuthServer()
        authServer?.onCodeReceived = { [weak self] code in
            guard let self = self else { return }
            self.status = "Code received! Authenticating..."
            self.exchangeCode(code) { success in
                if success {
                    self.status = "Connected ✓ (Auto-setup complete)"
                }
            }
        }
        authServer?.start()

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",     value: clientID),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: scope),
            URLQueryItem(name: "access_type",   value: "offline"),
            URLQueryItem(name: "prompt",        value: "consent"),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
            status = "Browser opened — sign in to continue..."
        }
    }

    /// Step 2 — exchange authorization code for tokens
    func exchangeCode(_ code: String, completion: @escaping (Bool) -> Void) {
        guard !clientID.isEmpty else { completion(false); return }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code":          code.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_id":     clientID,
            "client_secret": clientSecret,
            "redirect_uri":  redirectURI,
            "grant_type":    "authorization_code",
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
         .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { DispatchQueue.main.async { completion(false) }; return }

            if let access  = json["access_token"]  as? String,
               let refresh = json["refresh_token"] as? String,
               let expires = json["expires_in"]    as? Int {
                DispatchQueue.main.async {
                    self.saveTokens(access: access, refresh: refresh,
                                    expiry: Date().addingTimeInterval(Double(expires) - 60))
                    self.isConnected = true
                    self.status      = "Connected ✓"
                    completion(true)
                }
            } else {
                let err = json["error_description"] as? String ?? "Token exchange failed"
                DispatchQueue.main.async { self.status = err; completion(false) }
            }
        }.resume()
    }

    /// Refresh access token silently
    private func refreshIfNeeded(completion: @escaping (Bool) -> Void) {
        guard !refreshToken.isEmpty else {
            DispatchQueue.main.async { self.lastError = "No refresh token — reconnect Google Calendar" }
            completion(false); return
        }
        guard Date() >= tokenExpiry else { completion(true); return }

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "refresh_token": refreshToken,
            "client_id":     clientID,
            "client_secret": clientSecret,
            "grant_type":    "refresh_token",
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, response, netErr in
            if let e = netErr {
                DispatchQueue.main.async {
                    self.lastError = "Network error: \(e.localizedDescription)"
                    completion(false)
                }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { self.lastError = "Token refresh: unreadable response"; completion(false) }
                return
            }
            if let access  = json["access_token"] as? String,
               let expires = json["expires_in"]   as? Int {
                DispatchQueue.main.async {
                    self.accessToken = access
                    self.tokenExpiry = Date().addingTimeInterval(Double(expires) - 60)
                    UserDefaults.standard.set(access,           forKey: "gcal.accessToken")
                    UserDefaults.standard.set(self.tokenExpiry, forKey: "gcal.tokenExpiry")
                    self.lastError = ""
                    completion(true)
                }
            } else {
                let err = json["error"] as? String ?? ""
                let desc = json["error_description"] as? String ?? String(data: data, encoding: .utf8) ?? "unknown"
                DispatchQueue.main.async {
                    self.lastError = "Token refresh failed: \(err) — \(desc)"
                    CalendarDebugService.shared.logGoogleEvent("Token refresh", success: false, details: "\(err): \(desc)")
                    // If token is invalid/revoked, mark disconnected so user reconnects
                    if err == "invalid_grant" || err == "invalid_client" {
                        self.isConnected  = false
                        self.refreshToken = ""
                        UserDefaults.standard.removeObject(forKey: "gcal.refreshToken")
                        self.status = "Token expired — reconnect"
                    }
                    completion(false)
                }
            }
        }.resume()
    }

    // ── Push session to Google Calendar ──────────────────────────────────────

    func pushSession(_ session: StudySession, completion: ((Bool) -> Void)? = nil) {
        guard isConnected else { completion?(false); return }
        refreshIfNeeded { ok in
            guard ok else { completion?(false); return }
            self.createEvent(session: session, completion: completion)
        }
    }

    private func createEvent(session: StudySession, completion: ((Bool) -> Void)?) {
        let urlStr = "\(eventsURL)/\(calendarID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "primary")/events"
        guard let url = URL(string: urlStr) else { completion?(false); return }

        let iso = ISO8601DateFormatter()
        let summary     = "📚 \(session.subject)"
        let description = buildDescription(session)
        let colorID     = googleColorID(for: session.subject)

        let body: [String: Any] = [
            "summary":     summary,
            "description": description,
            "colorId":     colorID,
            "start": ["dateTime": iso.string(from: session.startTime),
                      "timeZone": TimeZone.current.identifier],
            "end":   ["dateTime": iso.string(from: session.endTime),
                      "timeZone": TimeZone.current.identifier],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion?(false); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)",   forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData

        URLSession.shared.dataTask(with: req) { data, response, netErr in
            if let e = netErr {
                DispatchQueue.main.async {
                    self.lastError = "Network: \(e.localizedDescription)"
                    completion?(false)
                }
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Google Calendar returns 201 Created for new events
            let success = statusCode == 200 || statusCode == 201
            if !success {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
                // Try to extract the error message from the JSON response
                let errMsg: String
                if let d = data,
                   let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let error = json["error"] as? [String: Any] {
                    let code    = error["code"] as? Int ?? statusCode
                    let message = error["message"] as? String ?? raw
                    errMsg = "[\(code)] \(message)"
                } else {
                    errMsg = "[\(statusCode)] \(raw.prefix(200))"
                }
                DispatchQueue.main.async {
                    self.lastError = "Push failed: \(errMsg)"
                    CalendarDebugService.shared.logGoogleEvent("Push session", success: false, details: errMsg)
                    completion?(false)
                }
                return
            }
            DispatchQueue.main.async {
                self.lastSyncDate = Date()
                self.lastError    = ""
                CalendarDebugService.shared.logGoogleEvent("Push session", success: true)
                completion?(true)
            }
        }.resume()
    }

    // ── Bulk sync — push all sessions ────────────────────────────────────────

    func syncAll(sessions: [StudySession], completion: @escaping (Int, Int) -> Void) {
        guard isConnected, !sessions.isEmpty else { completion(0, 0); return }
        isSyncing = true
        status    = "Syncing 0 / \(min(sessions.count, 100))…"

        let toSync = Array(sessions.prefix(100))
        // Use a background serial queue — never block the main thread
        let queue  = DispatchQueue(label: "gcal.sync", qos: .utility)
        var pushed = 0
        var failed = 0

        func syncNext(index: Int) {
            guard index < toSync.count else {
                DispatchQueue.main.async {
                    self.isSyncing    = false
                    self.lastSyncDate = Date()
                    self.status = pushed > 0
                        ? "Synced \(pushed) of \(toSync.count) sessions ✓"
                        : "Sync failed — check token and try again"
                    completion(pushed, failed)
                }
                return
            }
            let session = toSync[index]
            pushSession(session) { ok in
                if ok { pushed += 1 } else { failed += 1 }
                DispatchQueue.main.async {
                    self.status = "Syncing \(pushed + failed) / \(toSync.count)…"
                }
                // 200ms delay on background queue — respects rate limits without blocking UI
                queue.asyncAfter(deadline: .now() + 0.2) {
                    syncNext(index: index + 1)
                }
            }
        }

        queue.async { syncNext(index: 0) }
    }

    // ── Disconnect ────────────────────────────────────────────────────────────

    func disconnect() {
        accessToken  = ""
        refreshToken = ""
        tokenExpiry  = .distantPast
        isConnected  = false
        status       = "Disconnected"
        ["gcal.accessToken","gcal.refreshToken","gcal.tokenExpiry"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    // ── Exam → Google Calendar ────────────────────────────────────────────────

    /// Push an exam as a timed Google Calendar event with reminders
    /// Returns the created event ID via completion so it can be stored on ExamEntry
    func pushExam(_ exam: ExamEntry, completion: @escaping (String?) -> Void) {
        guard isConnected else { completion(nil); return }
        refreshIfNeeded { ok in
            guard ok else { completion(nil); return }
            self.createExamEvent(exam: exam, completion: completion)
        }
    }

    private func createExamEvent(exam: ExamEntry, completion: @escaping (String?) -> Void) {
        let urlStr = "\(eventsURL)/\(calendarID)/events"
        guard let url = URL(string: urlStr) else { completion(nil); return }

        let iso     = ISO8601DateFormatter()
        let tzID    = TimeZone.current.identifier
        let summary = "📝 Exam: \(exam.subject)"
        var desc    = "Exam for \(exam.subject)"
        if !exam.notes.isEmpty    { desc += "\n📋 \(exam.notes)" }
        if !exam.location.isEmpty { desc += "\n📍 \(exam.location)" }
        desc += "\n\nScheduled by StudyNotch"

        // Build start/end — use examTime if set, else all-day
        let startDict: [String: Any]
        let endDict  : [String: Any]

        if let t = exam.examTime {
            // Timed event — assume 2h duration for exam
            let examStart = t
            let examEnd   = t.addingTimeInterval(7200)
            startDict = ["dateTime": iso.string(from: examStart), "timeZone": tzID]
            endDict   = ["dateTime": iso.string(from: examEnd),   "timeZone": tzID]
        } else {
            // All-day event
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let dayStr = df.string(from: exam.date)
            startDict = ["date": dayStr]
            endDict   = ["date": dayStr]
        }

        // Reminders: 7 days, 3 days, 1 day, 2 hours before
        let reminders: [String: Any] = [
            "useDefault": false,
            "overrides": [
                ["method": "popup", "minutes": 7 * 24 * 60],
                ["method": "popup", "minutes": 3 * 24 * 60],
                ["method": "popup", "minutes": 1 * 24 * 60],
                ["method": "popup", "minutes": 120],
            ]
        ]

        var body: [String: Any] = [
            "summary":     summary,
            "description": desc,
            "colorId":     "11",   // Red — exams always red
            "start":       startDict,
            "end":         endDict,
            "reminders":   reminders,
        ]
        if !exam.location.isEmpty {
            body["location"] = exam.location
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData

        URLSession.shared.dataTask(with: req) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200 || statusCode == 201,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventID = json["id"] as? String
            else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
                print("[GCal] exam push failed: \(statusCode) — \(msg)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(eventID) }
        }.resume()
    }

    // ── Study reminders via macOS UserNotifications ───────────────────────────
    //
    //  Schedules local macOS notifications for each exam:
    //  7 days before, 3 days before, 1 day before, 2 hours before.
    //  Respects remindersSent to avoid duplicate notifications.

    // ── Today's calendar events (for notch badge) ────────────────────────────

    /// Fetch today's study sessions from Google Calendar
    func fetchTodayEvents(completion: ((Int) -> Void)? = nil) {
        guard isConnected else { completion?(0); return }
        refreshIfNeeded { ok in
            guard ok else { completion?(0); return }
            let cal = Calendar.current
            var startComps = cal.dateComponents([.year,.month,.day], from: Date())
            startComps.hour = 0; startComps.minute = 0; startComps.second = 0
            let endComps   = DateComponents(year: startComps.year, month: startComps.month,
                                            day: (startComps.day ?? 0) + 1)
            let dayStart = cal.date(from: startComps) ?? Date()
            let dayEnd   = cal.date(from: endComps)   ?? Date().addingTimeInterval(86400)

            let iso = ISO8601DateFormatter()
            // Build URL with URLComponents for reliability
            let calID = self.calendarID.isEmpty ? "primary" : self.calendarID
            guard var comps = URLComponents(string: self.eventsURL + "/" + calID + "/events") else {
                completion?(0); return
            }
            comps.queryItems = [
                URLQueryItem(name: "timeMin",       value: iso.string(from: dayStart)),
                URLQueryItem(name: "timeMax",       value: iso.string(from: dayEnd)),
                URLQueryItem(name: "singleEvents",  value: "true"),
                URLQueryItem(name: "orderBy",       value: "startTime"),
                URLQueryItem(name: "maxResults",    value: "20"),
            ]
            guard let url = comps.url else { completion?(0); return }
            var req = URLRequest(url: url)
            req.setValue("Bearer " + self.accessToken, forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]]
                else { DispatchQueue.main.async { completion?(0) }; return }

                let events: [CalendarEvent] = items.compactMap { item in
                    guard let summary = item["summary"] as? String else { return nil }
                    let startDict = item["start"] as? [String: Any]
                    let timeStr   = startDict?["dateTime"] as? String ?? startDict?["date"] as? String ?? ""
                    let startTime = iso.date(from: timeStr)
                    return CalendarEvent(title: summary, startTime: startTime)
                }
                DispatchQueue.main.async {
                    self.todayEvents = events
                    completion?(events.count)
                }
            }.resume()
        }
    }

    func scheduleStudyReminders(for exam: ExamEntry) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        // Request permission first
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            self.scheduleExamNotifications(exam: exam, center: center)
        }
    }

    private func scheduleExamNotifications(exam: ExamEntry, center: UNUserNotificationCenter) {
        let triggers: [(daysBefore: Int, title: String, body: String)] = [
            (7, "📚 Study Reminder", "\(exam.subject) exam in 7 days — start reviewing now"),
            (3, "⚠️ Exam in 3 Days",  "\(exam.subject) exam approaching — intensive review time"),
            (1, "🚨 Exam Tomorrow",   "\(exam.subject) exam is tomorrow — final review!"),
            (0, "⏰ Exam Today",       "\(exam.subject) exam is today — good luck! 🎓"),
        ]

        for trigger in triggers {
            let fireDate = Calendar.current.date(
                byAdding: .day, value: -trigger.daysBefore, to: exam.date
            ) ?? exam.date

            // Don't schedule if the date is in the past
            guard fireDate > Date() else { continue }

            let content        = UNMutableNotificationContent()
            content.title      = trigger.title
            content.body       = trigger.body
            content.sound      = .default
            content.categoryIdentifier = "EXAM_REMINDER"

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let notifTrigger = UNCalendarNotificationTrigger(
                dateMatching: components, repeats: false
            )
            let id = "exam_\(exam.id.uuidString)_\(trigger.daysBefore)d"
            let request = UNNotificationRequest(
                identifier: id, content: content, trigger: notifTrigger
            )
            center.add(request) { err in
                if let e = err { print("[Notif] failed: \(e)") }
            }
        }
    }

    func cancelExamReminders(for exam: ExamEntry) {
        let ids = [7,3,1,0].map { "exam_\(exam.id.uuidString)_\($0)d" }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // ── Credentials setters ───────────────────────────────────────────────────

    func setCredentials(clientID: String, clientSecret: String) {
        self.clientID     = clientID
        self.clientSecret = clientSecret
        UserDefaults.standard.set(clientID,     forKey: "gcal.clientID")
        UserDefaults.standard.set(clientSecret, forKey: "gcal.clientSecret")
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func saveTokens(access: String, refresh: String, expiry: Date) {
        accessToken  = access
        refreshToken = refresh
        tokenExpiry  = expiry
        UserDefaults.standard.set(access,  forKey: "gcal.accessToken")
        UserDefaults.standard.set(refresh, forKey: "gcal.refreshToken")
        UserDefaults.standard.set(expiry,  forKey: "gcal.tokenExpiry")
    }

    private func buildDescription(_ s: StudySession) -> String {
        var lines = ["⏱ Duration: \(fmtDur(s.duration))"]
        if s.difficulty > 0 {
            lines.append("⭐ Difficulty: \(String(repeating: "★", count: s.difficulty))\(String(repeating: "☆", count: 5 - s.difficulty))")
        }
        if !s.distractions.isEmpty {
            lines.append("⚡ Distractions: \(s.distractions.count)")
        }
        if !s.notes.isEmpty {
            lines.append("📝 \(s.notes)")
        }
        if s.isManual { lines.append("✏️ Manually logged") }
        lines.append("\nLogged by StudyNotch")
        return lines.joined(separator: "\n")
    }

    private func fmtDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600, m = (Int(d) % 3600)/60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// Map subject hash to one of Google Calendar's 11 color IDs
    private func googleColorID(for subject: String) -> String {
        // Google Calendar accepts colorId "1" through "11" only
        let ids = ["1","2","3","4","5","6","7","8","9","10","11"]
        let idx = abs(subject.hashValue) % ids.count
        return ids[idx]   // idx 0..10 → "1".."11" — always valid
    }
}

import Network

// ── OAuth Local Auth Server ───────────────────────────────────────────────────
// Launches a tiny temporary local HTTP server on port 8080 to automatically
// receive the Google OAuth callback without making the user copy/paste the code.

class LocalAuthServer {
    var listener: NWListener?
    var onCodeReceived: ((String) -> Void)?

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: 8080)
            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    if let data = data, let request = String(data: data, encoding: .utf8) {
                        if let range = request.range(of: "code="),
                           let endRange = request.range(of: "&", range: range.upperBound..<request.endIndex) ?? request.range(of: " HTTP", range: range.upperBound..<request.endIndex) {
                            
                            let code = String(request[range.upperBound..<endRange.lowerBound])
                            DispatchQueue.main.async { self?.onCodeReceived?(code) }
                            
                            let html = """
                            HTTP/1.1 200 OK\r
                            Content-Type: text/html\r
                            Connection: close\r
                            \r
                            <html>
                            <body style='font-family: -apple-system, sans-serif; background: #000; color: #fff; text-align: center; padding-top: 20%;'>
                                <h2>StudyNotch</h2>
                                <h3 style='color: #4CAF50;'>✓ Authentication Successful</h3>
                                <p style='color: #888;'>You can close this tab and return to the app.</p>
                                <script>setTimeout(function() { window.close() }, 3000);</script>
                            </body>
                            </html>
                            """
                            let resData = html.data(using: .utf8)!
                            connection.send(content: resData, completion: .contentProcessed { _ in
                                connection.cancel()
                                self?.stop()
                            })
                        } else {
                            // If no code is present (e.g. favicon request), just close
                            connection.cancel()
                        }
                    }
                }
            }
            listener?.start(queue: .main)
        } catch {
            print("[GCal] Failed to start local auth server on 8080: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
