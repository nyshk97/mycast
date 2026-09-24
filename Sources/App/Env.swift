import Foundation

/// dev 版（mycast Dev）と常用版で変わる値をまとめる
enum Env {
    #if DEBUG
    static let isDev = true
    static let dataDirName = "mycast-dev"
    static let logFileName = "mycast-dev.log"
    #else
    static let isDev = false
    static let dataDirName = "mycast"
    static let logFileName = "mycast.log"
    #endif

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var versionLabel: String {
        isDev ? "mycast v\(version) (dev)" : "mycast v\(version)"
    }

    /// 履歴・使用回数の置き場。dev は別ディレクトリにして、実装途中のコードが常用の履歴を壊さないようにする。
    /// dev 版だけ `MYCAST_DATA_DIR` で差し替えられる（移行検証で旧データの fixture を読ませるため）
    static let dataDir: URL = {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["MYCAST_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(dataDirName, isDirectory: true)
    }()

    static var imagesDir: URL { dataDir.appendingPathComponent("images", isDirectory: true) }
    static var databaseURL: URL { dataDir.appendingPathComponent("mycast.sqlite") }

    static let logURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/mycast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(logFileName)
    }()
}
