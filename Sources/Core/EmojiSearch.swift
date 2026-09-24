import Foundation

/// 絵文字 1 件。Sources/Resources/emoji.json（scripts/gen-emoji.py が CLDR から生成）の 1 要素
struct EmojiEntry: Codable, Equatable {
    /// 絵文字そのもの
    var e: String
    /// 英語名
    var n: String
    /// 日本語名（CLDR に無ければ nil）
    var j: String?
    /// 検索キーワード（英語・日本語）。絵文字画面は IME を許すので、日本語はかなキーで切り替えて引く
    var k: [String]
    /// グループ（Smileys & Emotion 等）
    var g: String
}

enum EmojiSearch {
    /// 空の検索語なら元の順序のまま全件。それ以外は名前 > キーワード の一致で並べる
    static func search(_ query: String, in entries: [EmojiEntry], usage: [String: Usage] = [:], now: Date = Date()) -> [EmojiEntry] {
        let q = FuzzyMatcher.normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        let tokens = q.split(separator: " ").map(String.init)
        var scored: [(EmojiEntry, Int, Int)] = []
        for (i, entry) in entries.enumerated() {
            var total = 0
            var ok = true
            for t in tokens {
                guard let s = tokenScore(t, entry) else { ok = false; break }
                total += s
            }
            guard ok else { continue }
            scored.append((entry, total + Frecency.bonus(usage[entry.e], now: now), i))
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
        return scored.map(\.0)
    }

    private static func tokenScore(_ t: String, _ entry: EmojiEntry) -> Int? {
        let name = FuzzyMatcher.normalize(entry.n)
        if name == t { return 1000 }
        let nameWords = FuzzyMatcher.splitWords(name)
        if name.hasPrefix(t) { return 800 }
        if nameWords.contains(where: { $0.hasPrefix(t) }) { return 700 }
        var best: Int?
        for k in entry.k {
            let nk = FuzzyMatcher.normalize(k)
            let s: Int?
            if nk == t { s = 650 } else if nk.hasPrefix(t) { s = 550 } else if nk.contains(t) { s = 300 } else { s = nil }
            if let s, s > (best ?? 0) { best = s }
        }
        if let best { return best }
        if name.contains(t) { return 250 }
        return nil
    }
}
