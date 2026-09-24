import Foundation

/// 使用履歴（起動回数と最終使用日時）から並べ替えの加点を作る。
/// 回数に時間減衰をかける（半減期 14 日）ので、昔に大量に開いたアプリが居座らない。
struct Usage: Equatable {
    var count: Int
    var lastUsed: Date
}

enum Frecency {
    static let halfLifeDays = 14.0

    static func value(_ usage: Usage?, now: Date) -> Double {
        guard let usage else { return 0 }
        let days = max(0, now.timeIntervalSince(usage.lastUsed) / 86_400)
        return Double(usage.count) * pow(0.5, days / halfLifeDays)
    }

    /// 一致点に足す加点（0〜200）
    static func bonus(_ usage: Usage?, now: Date) -> Int {
        let v = value(usage, now: now)
        guard v > 0 else { return 0 }
        return min(200, Int(60 * log2(1 + v)))
    }
}

/// ルート検索の候補を並べる。エイリアスに完全一致した候補は常に 1 位
struct RankInput {
    var id: String
    var keys: [String]
    var alias: String?
    var usage: Usage?
}

enum Ranker {
    static let aliasScore = 100_000

    static func rank(query: String, items: [RankInput], now: Date, limit: Int = 30) -> [String] {
        let q = FuzzyMatcher.normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var scored: [(id: String, score: Int, order: Int)] = []
        for (i, item) in items.enumerated() {
            if let alias = item.alias, FuzzyMatcher.normalize(alias) == q {
                scored.append((item.id, aliasScore, i))
                continue
            }
            guard let s = FuzzyMatcher.bestScore(query: q, keys: item.keys) else { continue }
            scored.append((item.id, s + Frecency.bonus(item.usage, now: now), i))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(limit).map(\.id)
    }
}
