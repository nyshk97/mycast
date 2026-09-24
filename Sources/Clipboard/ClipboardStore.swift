import AppKit
import CryptoKit

/// 履歴 1 件
struct ClipItem: Identifiable, Equatable {
    let id: Int64
    let kind: ClipboardPolicy.Kind
    /// テキストの本文、またはファイル参照の改行区切りパス
    let text: String?
    let imageFile: String?
    let width: Int?
    let height: Int?
    let sourceApp: String?
    let lastCopiedAt: Date

    var fileURLs: [URL] {
        guard kind == .file, let text else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var title: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = t.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? t
            return String(firstLine.prefix(200))
        case .image:
            if let width, let height { return "Image (\(width)×\(height))" }
            return "Image"
        case .file:
            let urls = fileURLs
            if urls.count == 1 { return urls[0].lastPathComponent }
            return "\(urls.first?.lastPathComponent ?? "") +\(urls.count - 1) more"
        }
    }
}

/// クリップボード履歴の保存先（SQLite ＋ 画像ファイル）
final class ClipboardStore {
    private let db: Database
    private let imagesDir: URL

    init(db: Database, imagesDir: URL) {
        self.db = db
        self.imagesDir = imagesDir
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 同じ内容が既にあれば先頭へ移す（last_copied_at を更新）。無ければ足す。戻り値は行の id
    @discardableResult
    func record(kind: ClipboardPolicy.Kind, text: String?, imageData: Data?, width: Int?, height: Int?,
                sourceApp: String?, now: Date = Date()) -> Int64? {
        let hash: String
        if kind == .image, let imageData {
            hash = Self.hash(Data(ClipboardPolicy.dedupeKey(kind: .image, payload: "").utf8) + imageData)
        } else {
            hash = Self.hash(Data(ClipboardPolicy.dedupeKey(kind: kind, payload: text ?? "").utf8))
        }
        let t = now.timeIntervalSince1970
        do {
            if let existing = try db.query("SELECT id FROM clipboard WHERE dedupe_hash = ?;", [.text(hash)], { $0.int(0) }).first {
                try db.run("UPDATE clipboard SET last_copied_at = ?, source_app = ? WHERE id = ?;",
                           [.double(t), sourceApp.map { .text($0) } ?? .null, .int(existing)])
                return existing
            }
            var imageFile: String?
            if kind == .image, let imageData {
                let name = "\(hash).png"
                try imageData.write(to: imagesDir.appendingPathComponent(name), options: .atomic)
                imageFile = name
            }
            try db.run("""
                INSERT INTO clipboard(kind, text, image_file, width, height, dedupe_hash, source_app, created_at, last_copied_at)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [.text(kind.rawValue), text.map { .text($0) } ?? .null, imageFile.map { .text($0) } ?? .null,
                      width.map { .int(Int64($0)) } ?? .null, height.map { .int(Int64($0)) } ?? .null,
                      .text(hash), sourceApp.map { .text($0) } ?? .null, .double(t), .double(t)])
            return db.lastInsertRowID
        } catch {
            Log.write("clipboard.record_failed \(error)")
            return nil
        }
    }

    func bump(id: Int64, now: Date = Date()) {
        _ = try? db.run("UPDATE clipboard SET last_copied_at = ? WHERE id = ?;", [.double(now.timeIntervalSince1970), .int(id)])
    }

    /// 新しい順。検索語があればテキスト・ファイルパスの部分一致で絞る（画像は "image" で引ける）
    func list(query: String, limit: Int = 300) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var sql = "SELECT id, kind, text, image_file, width, height, source_app, last_copied_at FROM clipboard"
        var binds: [Database.Value] = []
        if !q.isEmpty {
            let escaped = q.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            let matchesImage = "image".hasPrefix(q.lowercased()) || "画像".hasPrefix(q)
            sql += " WHERE (text LIKE ? ESCAPE '\\'\(matchesImage ? " OR kind = 'image'" : ""))"
            binds = [.text("%\(escaped)%")]
        }
        sql += " ORDER BY last_copied_at DESC LIMIT \(limit);"
        return (try? db.query(sql, binds) { row in
            ClipItem(id: row.int(0), kind: ClipboardPolicy.Kind(rawValue: row.text(1) ?? "text") ?? .text,
                     text: row.text(2), imageFile: row.text(3),
                     width: row.isNull(4) ? nil : Int(row.int(4)), height: row.isNull(5) ? nil : Int(row.int(5)),
                     sourceApp: row.text(6), lastCopiedAt: Date(timeIntervalSince1970: row.double(7)))
        }) ?? []
    }

    func imageURL(_ item: ClipItem) -> URL? {
        item.imageFile.map { imagesDir.appendingPathComponent($0) }
    }

    /// 保存期間を過ぎたものを消す。画像ファイルも一緒に消し、どの行からも参照されない画像も掃除する
    func purge(now: Date = Date()) {
        let cutoff = ClipboardPolicy.cutoff(now: now).timeIntervalSince1970
        do {
            let deleted = try db.run("DELETE FROM clipboard WHERE last_copied_at < ?;", [.double(cutoff)])
            let referenced = Set(try db.query("SELECT image_file FROM clipboard WHERE image_file IS NOT NULL;") { $0.text(0) ?? "" })
            var removedFiles = 0
            let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path)) ?? []
            for f in files where !referenced.contains(f) {
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f))
                removedFiles += 1
            }
            Log.write("clipboard.purged rows=\(deleted) files=\(removedFiles)")
        } catch {
            Log.write("clipboard.purge_failed \(error)")
        }
    }
}
