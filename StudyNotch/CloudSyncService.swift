import Foundation
import Observation
import CloudKit
import Combine
import UserNotifications

// ── iCloud Sync via CloudKit ──────────────────────────────────────────────────
// IMPORTANT: CKContainer is created lazily only when the user enables sync.
// Creating it at init time crashes if the app has no iCloud entitlement signed.

@Observable
final class CloudSyncService {
    static let shared = CloudSyncService()

     var status   : String = "Not synced"
     var isSyncing: Bool   = false

    var enabled: Bool {
        get { false }
        set { /* Disabled to prevent crash without provisioning profile */ }
    }

    private var _container: AnyObject? = nil
    private var container : CKContainer? {
        return nil // Disabled to prevent fatal framework crash
    }
    private var db    : CKDatabase?  { container?.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(
        zoneName  : "StudyNotchZone",
        ownerName : CKCurrentUserDefaultName
    )

    // ── Setup (called only when user toggles ON) ──────────────────────────────

    func setup() {
        guard enabled else { return }

        // Check iCloud is available before doing anything
        guard let container = container else { return }
        container.accountStatus { [weak self] status, error in
            guard status == .available else {
                DispatchQueue.main.async {
                    self?.status = "iCloud not available — sign in to iCloud in System Settings"
                }
                return
            }
            self?.db?.save(CKRecordZone(zoneID: self!.zoneID)) { _, _ in }
            DispatchQueue.main.async { self?.status = "iCloud connected" }
        }
    }

    // ── Push local → iCloud ───────────────────────────────────────────────────

    func pushSession(_ session: StudySession) {
        guard enabled, let db = db else { return }
        let recordID = CKRecord.ID(recordName: session.id.uuidString, zoneID: zoneID)
        let record   = CKRecord(recordType: "StudySession", recordID: recordID)
        record["subject"]    = session.subject    as CKRecordValue
        record["notes"]      = session.notes      as CKRecordValue
        record["difficulty"] = session.difficulty as CKRecordValue
        record["mode"]       = session.mode       as CKRecordValue
        record["date"]       = session.date       as CKRecordValue
        record["startTime"]  = session.startTime  as CKRecordValue
        record["endTime"]    = session.endTime    as CKRecordValue
        record["duration"]   = session.duration   as CKRecordValue
        if let data = try? JSONEncoder().encode(session.distractions),
           let str  = String(data: data, encoding: .utf8) {
            record["distractions"] = str as CKRecordValue
        }
        db.save(record) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.status = error == nil
                    ? "Synced \(self?.fmtNow() ?? "")"
                    : "Sync error: \(error!.localizedDescription)"
            }
        }
    }

    // ── Pull iCloud → local ───────────────────────────────────────────────────

    func pull(completion: @escaping ([StudySession]) -> Void) {
        guard enabled, let db = db else { completion([]); return }
        DispatchQueue.main.async { self.isSyncing = true; self.status = "Syncing…" }

        let query = CKQuery(recordType: "StudySession",
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]

        let op = CKQueryOperation(query: query)
        op.zoneID = zoneID
        var fetched: [CKRecord] = []
        op.recordMatchedBlock = { _, result in
            if case .success(let r) = result { fetched.append(r) }
        }
        op.queryResultBlock = { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isSyncing = false
                if case .failure(let e) = result {
                    self.status = "Pull failed: \(e.localizedDescription)"
                    completion([]); return
                }
                let sessions = fetched.compactMap { self.record(toSession: $0) }
                self.status  = "Synced \(self.fmtNow())"
                completion(sessions)
            }
        }
        db.add(op)
    }

    func mergeFromCloud() {
        pull { cloudSessions in
            let store    = SessionStore.shared
            let localIDs = Set(store.sessions.map { $0.id })
            let newOnes  = cloudSessions.filter { !localIDs.contains($0.id) }
            guard !newOnes.isEmpty else { return }
            newOnes.forEach { store.sessions.append($0) }
            store.sessions.sort { $0.startTime > $1.startTime }
            store.persistPublic()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func record(toSession r: CKRecord) -> StudySession? {
        guard let subject   = r["subject"]   as? String,
              let startTime = r["startTime"] as? Date,
              let endTime   = r["endTime"]   as? Date,
              let duration  = r["duration"]  as? Double
        else { return nil }
        var s = StudySession(
            subject   : subject,
            notes     : r["notes"]      as? String ?? "",
            difficulty: r["difficulty"] as? Int    ?? 0,
            mode      : r["mode"]       as? String ?? StudyMode.college.rawValue,
            date      : r["date"]       as? Date   ?? Calendar.current.startOfDay(for: startTime),
            startTime : startTime, endTime: endTime, duration: duration
        )
        s.id = UUID(uuidString: r.recordID.recordName) ?? UUID()
        if let jsonStr = r["distractions"] as? String,
           let data    = jsonStr.data(using: .utf8),
           let dists   = try? JSONDecoder().decode([DistractionEvent].self, from: data) {
            s.distractions = dists
        }
        return s
    }

    private func fmtNow() -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: Date())
    }
}
