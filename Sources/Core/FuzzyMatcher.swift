import Foundation

/// 検索語と候補文字列のあいまい一致。アプリ名・設定パネル名・コマンド名の検索に使う。
///
/// 加点の順位（高い順）: 完全一致 > 先頭一致 > 単語頭一致 > 頭文字一致 > 部分一致 > 飛び飛びの一致。
/// 空白区切りの複数語は、すべての語がどこかに一致したときだけ一致とみなす。
enum FuzzyMatcher {
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// 一致しなければ nil。大きいほど良い
    static func score(query: String, candidate: String) -> Int? {
        let q = normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let c = normalize(candidate)
        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            // 複数語: 各語が候補のどこかに一致すること（"sys set" → "system settings"）
            var total = 0
            for t in tokens {
                guard let s = singleScore(t, c) else { return nil }
                total += s
            }
            return total / tokens.count
        }
        return singleScore(q, c)
    }

    private static func singleScore(_ q: String, _ c: String) -> Int? {
        if c == q { return 1000 }
        if c.hasPrefix(q) { return 900 - min(c.count - q.count, 50) }
        let words = splitWords(c)
        if words.dropFirst().contains(where: { $0.hasPrefix(q) }) { return 700 - min(c.count - q.count, 50) }
        if q.count >= 2 {
            let initials = String(words.compactMap(\.first))
            if initials.hasPrefix(q) { return 600 }
        }
        if c.contains(q) { return 500 - min(c.count - q.count, 50) }
        if q.count >= 2, let s = subsequenceScore(q, c) { return s }
        return nil
    }

    /// 空白・ハイフン・ドット・大文字境界などで単語に分ける（正規化後なので大文字境界は見ない）
    static func splitWords(_ c: String) -> [String] {
        c.split(whereSeparator: { " -_.·&/()".contains($0) }).map(String.init)
    }

    /// q の文字が c に順番どおり現れれば一致。連続して一致した文字が多いほど高い（最大 300）
    private static func subsequenceScore(_ q: String, _ c: String) -> Int? {
        var qi = q.startIndex
        var consecutive = 0
        var bonus = 0
        var prevMatched = false
        for ch in c {
            guard qi < q.endIndex else { break }
            if ch == q[qi] {
                if prevMatched { consecutive += 1; bonus += consecutive * 10 } else { consecutive = 0 }
                prevMatched = true
                qi = q.index(after: qi)
            } else {
                prevMatched = false
            }
        }
        guard qi == q.endIndex else { return nil }
        return min(100 + bonus, 300)
    }

    /// 候補の複数キー（表示名・英語名・ローマ字名）の最高点
    static func bestScore(query: String, keys: [String]) -> Int? {
        keys.compactMap { score(query: query, candidate: $0) }.max()
    }
}
