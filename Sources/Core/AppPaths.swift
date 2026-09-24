import Foundation

/// アプリ一覧の収集で使う判定（純粋関数）
enum AppPathRules {
    /// `Foo.app/Contents/Library/LoginItems/Bar.app` のようなアプリ内ヘルパーを除外する
    static func isNestedApp(_ path: String) -> Bool {
        path.components(separatedBy: "/").filter { $0.hasSuffix(".app") }.count > 1
    }

    /// 日本語などの表示名をローマ字にする（ABC 入力で「メモ」を memo で引くため）。
    /// 変換できない・元から ASCII なら nil
    static func romanized(_ name: String) -> String? {
        guard name.unicodeScalars.contains(where: { !$0.isASCII }) else { return nil }
        let m = NSMutableString(string: name)
        CFStringTransform(m, nil, kCFStringTransformToLatin, false)
        CFStringTransform(m, nil, kCFStringTransformStripCombiningMarks, false)
        let s = (m as String).replacingOccurrences(of: "ー", with: "")
        guard s != name, s.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        return s
    }
}
