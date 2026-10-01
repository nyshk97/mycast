import CoreGraphics

/// 画面に出ているウィンドウ 1 枚（CGWindowListCopyWindowInfo から。持ち主・レイヤー・大きさだけなら画面収録の許可は要らない）
struct ScreenWindow: Equatable {
    var bundleID: String?
    var layer: Int
    var size: CGSize
}

/// memode（左 Shift のダブルタップで出すポップアップのエディタ）から開いたときの戻り先（純粋関数）。
///
/// memode のパネルは nonactivating なので、前面のアプリは後ろのアプリのまま。⌃L を押した時点で memode のパネルが出ていれば、
/// キー入力は memode にあった（memode は mycast 以外へキーが移ると隠れる）。閉じたあとは `memode://paste`・`memode://focus` で返す
enum MemodeHandoff {
    /// bundle id → URL スキーム
    static let schemes = ["local.nyshk97.memode": "memode", "local.nyshk97.memode.dev": "memode-dev"]
    /// NSWindow.Level.floating（memode のパネルのレベル）
    static let floatingLayer = 3

    /// `windows` は手前から順。常用版と dev 版が両方出ていたら手前の方に返す。
    /// memode のメニューバーのアイテム（レイヤー 25）はレイヤーで外す（パネルの最小は 480×300）
    static func scheme(windows: [ScreenWindow]) -> String? {
        for w in windows {
            guard let id = w.bundleID, let scheme = schemes[id] else { continue }
            if w.layer == floatingLayer && w.size.width >= 200 && w.size.height >= 100 { return scheme }
        }
        return nil
    }
}
