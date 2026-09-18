import CloudKit
import UIKit

/// Someone else's challenge, read from the public CloudKit database.
struct RemoteProfile: Equatable {
    var code: String
    var name: String
    var attemptID: String
    var startKey: String
    var friend: String
    var avatar: UIImage?
}

/// Public database layout:
///   Profile  "p<code>"                  name, attemptID, startKey, friend (queryable), avatar
///   Day      "d<code>_<attempt>_<n>"    done (comma list), note, hasPhoto, dayKey, photo
/// Records are world readable and only their creator can change them.
enum Sync {
    static var container: CKContainer { CKContainer(identifier: Hard.container) }
    static var db: CKDatabase { container.publicCloudDatabase }

    static func profileID(_ code: String) -> CKRecord.ID { .init(recordName: "p" + code) }
    static func dayID(_ code: String, _ attempt: String, _ n: Int) -> CKRecord.ID { .init(recordName: "d\(code)_\(attempt)_\(n)") }

    static func myCode() async throws -> String {
        try await container.userRecordID().recordName
    }

    /// Sends everything the app or widget changed since the last push.
    static func push() async throws {
        var s = HardStore.load()
        guard s.signedIn else { return }
        if s.myCode.isEmpty {
            let code = try await myCode()
            s = HardActions.apply { $0.myCode = code }
        }
        var records: [CKRecord] = []
        if s.profileDirty { records.append(profileRecord(s)) }
        for n in s.dirtyDays.sorted() { records.append(dayRecord(s, n)) }
        guard !records.isEmpty else { return }

        let (saved, _) = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
        var fresh = HardStore.load()
        var firstError: Error?
        for (id, result) in saved {
            switch result {
            case .success:
                if id == profileID(s.myCode) { fresh.profileDirty = false; continue }
                if let n = Int(id.recordName.split(separator: "_").last ?? ""), fresh.day(n) == s.day(n) { fresh.dirtyDays.remove(n) }
            case .failure(let e):
                firstError = firstError ?? e
            }
        }
        HardStore.save(fresh)
        if let firstError { throw firstError }
    }

    static func profileRecord(_ s: HardState) -> CKRecord {
        let r = CKRecord(recordType: "Profile", recordID: profileID(s.myCode))
        r["name"] = s.firstName as CKRecordValue
        r["attemptID"] = s.attemptID as CKRecordValue
        r["startKey"] = s.startKey as CKRecordValue
        r["friend"] = s.friendCode as CKRecordValue
        r["avatar"] = FileManager.default.fileExists(atPath: HardStore.avatarURL.path) ? CKAsset(fileURL: HardStore.avatarURL) : nil
        return r
    }

    static func dayRecord(_ s: HardState, _ n: Int) -> CKRecord {
        let d = s.day(n)
        let r = CKRecord(recordType: "Day", recordID: dayID(s.myCode, s.attemptID, n))
        r["done"] = HardTask.all.map(\.id).filter { d.done.contains($0) }.joined(separator: ",") as CKRecordValue
        r["note"] = d.note as CKRecordValue
        r["hasPhoto"] = (d.hasPhoto ? 1 : 0) as CKRecordValue
        r["dayKey"] = DayMath.key(DayMath.date(day: n, startKey: s.startKey)) as CKRecordValue
        let photo = HardStore.photoURL(owner: "me", attempt: s.attemptID, day: n)
        r["photo"] = d.hasPhoto && FileManager.default.fileExists(atPath: photo.path) ? CKAsset(fileURL: photo) : nil
        return r
    }

    static func fetchProfile(_ code: String) async throws -> RemoteProfile? {
        do {
            let r = try await db.record(for: profileID(code))
            var avatar: UIImage?
            if let url = (r["avatar"] as? CKAsset)?.fileURL { avatar = UIImage(contentsOfFile: url.path) }
            return RemoteProfile(
                code: code,
                name: r["name"] as? String ?? "Friend",
                attemptID: r["attemptID"] as? String ?? "",
                startKey: r["startKey"] as? String ?? "",
                friend: r["friend"] as? String ?? "",
                avatar: avatar
            )
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    /// Day records 1...n without photos (those load one at a time when opened).
    static func fetchDays(_ code: String, attempt: String, upTo n: Int) async throws -> [Int: DayRecord] {
        guard n >= 1 else { return [:] }
        let ids = (1...min(n, Hard.days)).map { dayID(code, attempt, $0) }
        let results = try await db.records(for: ids, desiredKeys: ["done", "note", "hasPhoto"])
        var out: [Int: DayRecord] = [:]
        for (i, id) in ids.enumerated() {
            guard case .success(let r)? = results[id] else { continue }
            let done = (r["done"] as? String ?? "").split(separator: ",").map(String.init)
            out[i + 1] = DayRecord(done: Set(done), note: r["note"] as? String ?? "", hasPhoto: (r["hasPhoto"] as? Int64 ?? 0) == 1)
        }
        return out
    }

    /// Downloads one progress picture into the local cache and returns its file.
    static func photo(code: String, attempt: String, day: Int, to url: URL) async -> URL? {
        guard let r = try? await db.record(for: dayID(code, attempt, day)),
              let asset = (r["photo"] as? CKAsset)?.fileURL else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (try? FileManager.default.copyItem(at: asset, to: url)) != nil ? url : nil
    }

    /// Whoever added you as their friend, so both people appear without a second invite.
    static func findFollower(of code: String) async throws -> String? {
        let q = CKQuery(recordType: "Profile", predicate: NSPredicate(format: "friend == %@", code))
        let (matches, _) = try await db.records(matching: q, desiredKeys: ["name"], resultsLimit: 5)
        return matches.map { String($0.0.recordName.dropFirst()) }.first { $0 != code }
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? CKError else { return error.localizedDescription }
        switch e.code {
        case .notAuthenticated: return "Sign in to iCloud in the Settings app to sync."
        case .networkUnavailable, .networkFailure: return "No connection. Changes will sync when you are back online."
        default: return e.localizedDescription
        }
    }
}
