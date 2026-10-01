import AppKit

/// memode への受け渡し（判定は `MemodeHandoff`）
enum Handoff {
    /// 今画面に出ている memode の URL スキーム（出ていなければ nil）。mycast が前に出る前に呼ぶ
    static func memodeScheme() -> String? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var bundleIDs: [pid_t: String?] = [:]
        let windows: [ScreenWindow] = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return nil }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // アプリを引く回数を減らすための先絞り（判定そのものは MemodeHandoff）
            guard layer == MemodeHandoff.floatingLayer else { return nil }
            let id = bundleIDs[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            bundleIDs[pid] = id
            return ScreenWindow(bundleID: id, layer: layer, size: bounds.size)
        }
        return MemodeHandoff.scheme(windows: windows)
    }

    /// `memode://paste`（ペーストボードの中身を貼る）・`memode://focus`（キー入力を戻すだけ）。memode を前面にしない開き方で送る
    static func send(_ scheme: String, _ host: String) {
        guard let url = URL(string: "\(scheme)://\(host)") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error { Log.write("handoff.failed url=\(url.absoluteString) error=\(error.localizedDescription)") }
        }
        Log.write("handoff.sent url=\(url.absoluteString)")
    }
}
