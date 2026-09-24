import AppKit

/// ルート検索の候補 1 件
struct RootItem: Identifiable {
    enum Kind {
        case app(URL)
        case settingsPane(String)
        case command(LauncherMode)
        case system(SystemAction)
        case checkForUpdates
    }

    let id: String
    let title: String
    let subtitle: String?
    let typeLabel: String
    let kind: Kind
    let keys: [String]
    let alias: String?
    let iconPath: String?
    let symbolName: String?
}

/// アプリと設定パネルの一覧を持つ。アプリは NSMetadataQuery で集め、結果は DB にキャッシュする
/// （起動直後の最初の ⌃L でも候補が出るように、前回の一覧から始める）
final class AppIndex {
    static let appScopes: [String] = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]
    /// NSMetadataQuery の範囲外だが常用するもの
    static let extraApps = ["/System/Library/CoreServices/Finder.app"]

    private let db: Database
    private var query: NSMetadataQuery?
    private(set) var apps: [RootItem] = []
    private(set) var panes: [RootItem] = []
    let commands: [RootItem] = [
        RootItem(id: "cmd:clipboard", title: "Clipboard History", subtitle: "クリップボード履歴", typeLabel: "Command",
                 kind: .command(.clipboard), keys: ["Clipboard History", "クリップボード履歴", "kuripubodo"],
                 alias: "c", iconPath: nil, symbolName: "doc.on.clipboard"),
        RootItem(id: "cmd:emoji", title: "Search Emoji & Symbols", subtitle: "絵文字", typeLabel: "Command",
                 kind: .command(.emoji), keys: ["Search Emoji & Symbols", "Emoji", "絵文字", "emoji"],
                 alias: "e", iconPath: nil, symbolName: "face.smiling"),
    ]
    /// 常用版で Sparkle が動いているときだけ AppDelegate が入れる（dev 版・鍵の無いビルドでは出さない）
    var updateCommand: RootItem?
    static let checkForUpdatesItem = RootItem(
        id: "cmd:check-for-updates", title: "Check for Updates", subtitle: "アップデートを確認", typeLabel: "Command",
        kind: .checkForUpdates, keys: ["Check for Updates", "Update", "アップデートを確認", "appudeto"],
        alias: nil, iconPath: nil, symbolName: "arrow.down.circle")
    /// all の末尾に置く。同点のときは並び順で決まるので、打ち始め（`sl` 等）で
    /// 確認なしの Sleep がアプリより先に来て Enter 一発で走らないようにする
    let systemCommands: [RootItem] = SystemAction.allCases.map { a in
        RootItem(id: "sys:\(a.rawValue)", title: a.title, subtitle: a.subtitle, typeLabel: "System",
                 kind: .system(a), keys: a.keys,
                 alias: nil, iconPath: nil, symbolName: a.symbolName)
    }

    var all: [RootItem] { commands + (updateCommand.map { [$0] } ?? []) + apps + panes + systemCommands }

    init(db: Database) {
        self.db = db
        loadCache()
        panes = Self.collectSettingsPanes()
        Log.write("index.loaded apps=\(apps.count) panes=\(panes.count) (cache)")
    }

    // MARK: - Apps

    func startQuery() {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        q.searchScopes = Self.appScopes.filter { FileManager.default.fileExists(atPath: $0) }
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidUpdate, object: q)
        query = q
        q.start()
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        var paths: [String] = []
        for i in 0..<q.resultCount {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                paths.append(path)
            }
        }
        q.enableUpdates()
        var source = "spotlight"
        if paths.isEmpty {
            // インデックス再構築中などで 0 件のときはディレクトリを直接たどる
            paths = Self.scanDirectories()
            source = "scan"
        }
        paths += Self.extraApps.filter { FileManager.default.fileExists(atPath: $0) }
        let filtered = Array(Set(paths.filter { !AppPathRules.isNestedApp($0) && !$0.contains("/.") })).sorted()
        apps = filtered.map { Self.makeAppItem(path: $0, name: Self.displayName($0), english: Self.englishName($0)) }
        saveCache()
        Log.write("index.apps_updated source=\(source) count=\(apps.count)")
    }

    static func scanDirectories() -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        for scope in appScopes {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: scope), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                if url.pathExtension == "app" {
                    out.append(url.path)
                    e.skipDescendants()
                } else if e.level >= 3 {
                    e.skipDescendants()
                }
            }
        }
        return out
    }

    static func displayName(_ path: String) -> String {
        let n = FileManager.default.displayName(atPath: path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    static func englishName(_ path: String) -> String {
        let file = (path as NSString).lastPathComponent
        return file.hasSuffix(".app") ? String(file.dropLast(4)) : file
    }

    static func makeAppItem(path: String, name: String, english: String) -> RootItem {
        var keys = [name]
        if english != name { keys.append(english) }
        if let r = AppPathRules.romanized(name) { keys.append(r) }
        return RootItem(id: "app:\(path)", title: name, subtitle: english != name ? english : nil,
                        typeLabel: "Application", kind: .app(URL(fileURLWithPath: path)), keys: keys,
                        alias: nil, iconPath: path, symbolName: nil)
    }

    private func loadCache() {
        let rows = (try? db.query("SELECT path, name, english FROM app_cache ORDER BY path;") { row in
            (row.text(0) ?? "", row.text(1) ?? "", row.text(2) ?? "")
        }) ?? []
        apps = rows.filter { FileManager.default.fileExists(atPath: $0.0) }
            .map { Self.makeAppItem(path: $0.0, name: $0.1, english: $0.2) }
    }

    private func saveCache() {
        do {
            try db.exec("BEGIN;")
            try db.run("DELETE FROM app_cache;")
            for item in apps {
                guard case .app(let url) = item.kind else { continue }
                try db.run("INSERT INTO app_cache(path, name, english) VALUES(?, ?, ?);",
                           [.text(url.path), .text(item.title), .text(Self.englishName(url.path))])
            }
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
            Log.write("index.cache_save_failed \(error)")
        }
    }

    // MARK: - System Settings panes

    /// ExtensionKit のうちシステム設定のパネル（`com.apple.Settings.extension.ui`）で、
    /// `x-apple.systempreferences:` の URL で開けるものを集める
    static func collectSettingsPanes() -> [RootItem] {
        let dir = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let lang = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "ja"
        var out: [RootItem] = []
        for url in urls where url.pathExtension == "appex" {
            guard let bundle = Bundle(url: url), let info = bundle.infoDictionary,
                  let ex = info["EXAppExtensionAttributes"] as? [String: Any],
                  ex["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  let sa = ex["SettingsExtensionAttributes"] as? [String: Any],
                  sa["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
                  let bundleID = bundle.bundleIdentifier else { continue }
            let table = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Resources/InfoPlist.loctable"))
            func localized(_ l: String) -> String? {
                let d = table?[l] as? [String: Any]
                return (d?["CFBundleDisplayName"] as? String) ?? (d?["CFBundleName"] as? String)
            }
            let en = localized("en") ?? (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let local = localized(lang) ?? en
            var keys = [local]
            if en != local { keys.append(en) }
            if let r = AppPathRules.romanized(local) { keys.append(r) }
            out.append(RootItem(id: "pane:\(bundleID)", title: local, subtitle: en != local ? en : nil,
                                typeLabel: "System Settings", kind: .settingsPane(bundleID), keys: keys,
                                alias: nil, iconPath: "/System/Applications/System Settings.app", symbolName: nil))
        }
        return out.sorted { $0.title < $1.title }
    }
}

/// アイコンの取得はパス単位でキャッシュする（NSWorkspace の取得は候補表示のたびには重い）
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(path: String) -> NSImage {
        if let img = cache[path] { return img }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 32, height: 32)
        cache[path] = img
        return img
    }
}
