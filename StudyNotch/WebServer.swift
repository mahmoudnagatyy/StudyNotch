import Foundation
import Network

// ── Tiny HTTP server built into StudyNotch ────────────────────────────────────
// iPhone opens Safari → http://[mac-local-ip]:7788
// No App Store, no developer account, no iCloud needed.

final class WebServer {
    static let shared = WebServer()
    static let port: UInt16 = 7788

    private var listener: NWListener?
    private(set) var isRunning = false

    var localURL: String {
        guard let ip = localIPAddress() else { return "Not available" }
        return "http://\(ip):\(WebServer.port)"
    }

    // ── Start / Stop ──────────────────────────────────────────────────────────

    func start() {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params,
                                             on: NWEndpoint.Port(rawValue: WebServer.port)!) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.start(queue: .global(qos: .utility))
        isRunning = true
    }

    func stop() {
        listener?.cancel(); listener = nil; isRunning = false
    }

    // ── Connection handler ────────────────────────────────────────────────────

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let path = self.parsePath(request)
            let (status, mime, body) = self.route(path)
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(mime); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            let response = (header + body).data(using: .utf8)!
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private func parsePath(_ request: String) -> String {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.components(separatedBy: " ")
        return parts.count > 1 ? parts[1] : "/"
    }

    // ── Routes ────────────────────────────────────────────────────────────────

    private func route(_ path: String) -> (String, String, String) {
        switch path {
        case "/api/data":
            return ("200 OK", "application/json", jsonData())
        case "/api/toggle":
            DispatchQueue.main.async { StudyTimer.shared.toggle() }
            return ("200 OK", "application/json", "{\"ok\":true}")
        default:
            return ("200 OK", "text/html", htmlDashboard())
        }
    }

    // ── JSON API ──────────────────────────────────────────────────────────────

    private func jsonData() -> String {
        let store     = SessionStore.shared
        let timer     = StudyTimer.shared
        let modeStore = ModeStore.shared

        let todaySessions = store.sessions.filter {
            Calendar.current.isDateInToday($0.date)
        }

        let subjectTotals = store.subjectTotals.prefix(5).map { s in
            "{\"subject\":\"\(esc(s.subject))\",\"total\":\(Int(s.total/60))}"
        }.joined(separator: ",")

        let exams = modeStore.collegeSubjects.compactMap { sub -> String? in
            guard let ct = sub.countdownText else { return nil }
            return "{\"name\":\"\(esc(sub.name))\",\"countdown\":\"\(ct)\"}"
        }.joined(separator: ",")

        let recentSessions = store.sessions.prefix(5).map { s in
            let fmt = DateFormatter(); fmt.timeStyle = .short
            return "{\"subject\":\"\(esc(s.subject))\",\"duration\":\(Int(s.duration/60)),\"difficulty\":\(s.difficulty),\"time\":\"\(fmt.string(from: s.startTime))\"}"
        }.joined(separator: ",")

        let timerState = timer.state == .running ? "running" : timer.state == .paused ? "paused" : "idle"

        return """
        {
          "timer": {
            "elapsed": "\(timer.formattedTime)",
            "state": "\(timerState)"
          },
          "today": {
            "total": "\(formatDur(store.todayTotal))",
            "sessions": \(todaySessions.count)
          },
          "streak": \(streakDays()),
          "mode": "\(modeStore.currentMode.rawValue)",
          "semester": "\(esc(modeStore.semesterName))",
          "subjectTotals": [\(subjectTotals)],
          "exams": [\(exams)],
          "recentSessions": [\(recentSessions)]
        }
        """
    }

    // ── HTML Dashboard ────────────────────────────────────────────────────────

    private func htmlDashboard() -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <title>StudyNotch</title>
        <style>
          :root {
            --bg: #0a0a0f; --card: #13131a; --border: #222230;
            --green: #33ff88; --blue: #4da6ff; --orange: #ff9944;
            --purple: #aa66ff; --red: #ff5566; --text: #f0f0f8; --dim: #666680;
          }
          * { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
          body { background: var(--bg); color: var(--text); font-family: -apple-system, sans-serif;
                 min-height: 100vh; padding-bottom: 40px; }
          .header { padding: 56px 20px 20px; text-align: center; }
          .header h1 { font-size: 22px; font-weight: 700; }
          .header p  { font-size: 13px; color: var(--dim); margin-top: 4px; }
          .timer-card { margin: 0 16px 16px; background: var(--card);
                        border-radius: 20px; border: 1px solid var(--border);
                        padding: 28px 20px; text-align: center; }
          .timer-display { font-size: 52px; font-weight: 800; letter-spacing: -2px;
                           font-variant-numeric: tabular-nums; }
          .timer-display.running { color: var(--green); }
          .timer-display.paused  { color: var(--orange); }
          .timer-display.idle    { color: var(--dim); }
          .timer-label { font-size: 13px; color: var(--dim); margin-top: 6px; text-transform: uppercase; letter-spacing: 1px; }
          .btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px;
                 padding: 14px 32px; border-radius: 50px; border: none; font-size: 16px;
                 font-weight: 700; cursor: pointer; margin-top: 18px; transition: opacity .15s; }
          .btn:active { opacity: .7; }
          .btn-green  { background: var(--green);  color: #000; }
          .btn-orange { background: var(--orange); color: #000; }
          .btn-dim    { background: var(--border); color: var(--text); }
          .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
                  margin: 0 16px 16px; }
          .stat-card { background: var(--card); border-radius: 16px;
                       border: 1px solid var(--border); padding: 18px 16px; }
          .stat-value { font-size: 28px; font-weight: 800; }
          .stat-label { font-size: 12px; color: var(--dim); margin-top: 4px; }
          .section { margin: 0 16px 16px; }
          .section-title { font-size: 12px; font-weight: 600; color: var(--dim);
                           text-transform: uppercase; letter-spacing: 1px; margin-bottom: 10px; }
          .row { background: var(--card); border-radius: 14px; border: 1px solid var(--border);
                 padding: 14px 16px; margin-bottom: 8px; display: flex; align-items: center; gap: 12px; }
          .row-icon { width: 36px; height: 36px; border-radius: 10px; display: flex;
                      align-items: center; justify-content: center; font-size: 16px; flex-shrink: 0; }
          .row-main { flex: 1; min-width: 0; }
          .row-title { font-size: 15px; font-weight: 600; overflow: hidden;
                       text-overflow: ellipsis; white-space: nowrap; }
          .row-sub   { font-size: 12px; color: var(--dim); margin-top: 2px; }
          .row-right { font-size: 14px; font-weight: 700; flex-shrink: 0; }
          .bar-row   { margin-bottom: 12px; }
          .bar-label { display: flex; justify-content: space-between;
                       font-size: 13px; margin-bottom: 6px; }
          .bar-track { height: 8px; background: var(--border); border-radius: 4px; overflow: hidden; }
          .bar-fill  { height: 100%; border-radius: 4px; transition: width .5s ease; }
          .exam-badge { background: rgba(255,153,68,.15); border: 1px solid rgba(255,153,68,.3);
                        border-radius: 12px; padding: 14px 16px; margin-bottom: 8px;
                        display: flex; justify-content: space-between; align-items: center; }
          .exam-name { font-size: 14px; font-weight: 600; }
          .exam-countdown { font-size: 18px; font-weight: 800; color: var(--orange);
                            font-variant-numeric: tabular-nums; }
          .refresh-btn { display: block; margin: 20px auto 0; background: none;
                         border: 1px solid var(--border); color: var(--dim);
                         padding: 10px 24px; border-radius: 50px; font-size: 13px; cursor: pointer; }
          .dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
          .dot-green { background: var(--green); box-shadow: 0 0 6px var(--green); }
          .stars { color: var(--orange); font-size: 11px; }
          .mode-badge { display: inline-block; padding: 3px 10px; border-radius: 20px;
                        font-size: 11px; font-weight: 600; margin-left: 8px; }
          .mode-college  { background: rgba(77,166,255,.15); color: var(--blue); }
          .mode-personal { background: rgba(170,102,255,.15); color: var(--purple); }
        </style>
        </head>
        <body>

        <div class="header">
          <h1>📚 StudyNotch</h1>
          <p id="mode-label">Loading...</p>
        </div>

        <!-- Timer -->
        <div class="timer-card">
          <div class="timer-display idle" id="timer-display">--:--</div>
          <div class="timer-label" id="timer-label">Tap to start on Mac</div>
          <button class="btn btn-green" id="toggle-btn" onclick="toggleTimer()">▶ Start</button>
        </div>

        <!-- Stats grid -->
        <div class="grid">
          <div class="stat-card">
            <div class="stat-value" id="today-total" style="color:var(--green)">—</div>
            <div class="stat-label">Today</div>
          </div>
          <div class="stat-card">
            <div class="stat-value" id="streak" style="color:var(--orange)">—</div>
            <div class="stat-label">Day Streak 🔥</div>
          </div>
        </div>

        <!-- Exam countdowns -->
        <div class="section" id="exams-section" style="display:none">
          <div class="section-title">⏰ Upcoming Exams</div>
          <div id="exams-list"></div>
        </div>

        <!-- Subject breakdown -->
        <div class="section">
          <div class="section-title">📊 Top Subjects</div>
          <div id="subjects-list"></div>
        </div>

        <!-- Recent sessions -->
        <div class="section">
          <div class="section-title">🕐 Recent Sessions</div>
          <div id="sessions-list"></div>
        </div>

        <button class="refresh-btn" onclick="load()">↻ Refresh</button>
        <p style="text-align:center;color:var(--dim);font-size:11px;margin-top:16px">
          Auto-refreshes every 5s · Same WiFi required
        </p>

        <script>
        const COLORS = ['#4da6ff','#33ff88','#ff9944','#aa66ff','#ff5566','#00ccff','#ff66aa','#ffdd44'];
        function color(str) { let h=0; for(let c of str) h=(h*31+c.charCodeAt(0))%COLORS.length; return COLORS[Math.abs(h)]; }
        function stars(n) { return '★'.repeat(n)+'☆'.repeat(5-n); }

        async function load() {
          try {
            const r = await fetch('/api/data');
            const d = await r.json();
            render(d);
          } catch(e) {
            document.getElementById('timer-label').textContent = 'Cannot reach Mac — same WiFi?';
          }
        }

        function render(d) {
          // Mode label
          const badge = d.mode === 'College'
            ? '<span class="mode-badge mode-college">🎓 '+d.semester+'</span>'
            : '<span class="mode-badge mode-personal">📚 Personal</span>';
          document.getElementById('mode-label').innerHTML = 'Active mode ' + badge;

          // Timer
          const disp = document.getElementById('timer-display');
          const lbl  = document.getElementById('toggle-btn');
          disp.textContent = d.timer.elapsed;
          disp.className   = 'timer-display ' + d.timer.state;
          document.getElementById('timer-label').textContent =
            d.timer.state === 'running' ? 'Studying...' :
            d.timer.state === 'paused'  ? 'Paused' : 'Ready to study';
          lbl.textContent   = d.timer.state === 'running' ? '⏸ Pause' : '▶ Start';
          lbl.className     = 'btn ' + (d.timer.state === 'running' ? 'btn-orange' : 'btn-green');

          // Stats
          document.getElementById('today-total').textContent = d.today.total || '0m';
          document.getElementById('streak').textContent      = d.streak + 'd';

          // Exams
          const exSec  = document.getElementById('exams-section');
          const exList = document.getElementById('exams-list');
          if (d.exams && d.exams.length > 0) {
            exSec.style.display = 'block';
            exList.innerHTML = d.exams.map(e =>
              '<div class="exam-badge"><span class="exam-name">'+e.name+'</span><span class="exam-countdown">'+e.countdown+'</span></div>'
            ).join('');
          }

          // Subjects bars
          const maxMins = d.subjectTotals[0]?.total || 1;
          document.getElementById('subjects-list').innerHTML = d.subjectTotals.map(s => {
            const pct = Math.round(s.total / maxMins * 100);
            const hrs = s.total >= 60 ? Math.floor(s.total/60)+'h '+(s.total%60)+'m' : s.total+'m';
            return '<div class="bar-row">'
              + '<div class="bar-label"><span>'+s.subject+'</span><span style="color:var(--dim)">'+hrs+'</span></div>'
              + '<div class="bar-track"><div class="bar-fill" style="width:'+pct+'%;background:'+color(s.subject)+'"></div></div>'
              + '</div>';
          }).join('') || '<p style="color:var(--dim);font-size:13px">No sessions yet</p>';

          // Recent sessions
          document.getElementById('sessions-list').innerHTML = d.recentSessions.map(s =>
            '<div class="row">'
            + '<div class="row-icon" style="background:'+color(s.subject)+'22">'+s.subject[0].toUpperCase()+'</div>'
            + '<div class="row-main"><div class="row-title">'+s.subject+'</div>'
            + '<div class="row-sub"><span class="stars">'+stars(s.difficulty)+'</span> · '+s.time+'</div></div>'
            + '<div class="row-right" style="color:'+color(s.subject)+'">'+s.duration+'m</div>'
            + '</div>'
          ).join('') || '<p style="color:var(--dim);font-size:13px">No sessions yet</p>';
        }

        async function toggleTimer() {
          await fetch('/api/toggle');
          setTimeout(load, 300);
        }

        // Auto-refresh every 5 seconds (updates timer display)
        load();
        setInterval(load, 5000);
        </script>
        </body>
        </html>
        """
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            let addr  = p.pointee.ifa_addr.pointee
            if (flags & IFF_UP) != 0 && addr.sa_family == UInt8(AF_INET) {
                let name = String(cString: p.pointee.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(p.pointee.ifa_addr, socklen_t(addr.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return address
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: " ")
    }

    private func formatDur(_ d: TimeInterval) -> String {
        let h = Int(d)/3600; let m = (Int(d)%3600)/60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m" : "\(Int(d))s"
    }

    private func streakDays() -> Int {
        let cal = Calendar.current
        var n = 0; var day = Date()
        while SessionStore.shared.sessions.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) {
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }
}
