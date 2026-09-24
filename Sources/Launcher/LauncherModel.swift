import AppKit
import Combine

enum LauncherMode: String {
    case root, clipboard, emoji

    var title: String {
        switch self {
        case .root: return ""
        case .clipboard: return "Clipboard History"
        case .emoji: return "Emoji"
        }
    }

    var placeholder: String {
        switch self {
        case .root: return "アプリ・設定を検索…"
        case .clipboard: return "履歴を検索…"
        case .emoji: return "絵文字を検索…"
        }
    }
}

/// パネルの表示状態。検索語・モード・候補・選択位置を持つ（実行は LauncherController）
final class LauncherModel: ObservableObject {
    static let emojiColumns = 10
    static let recentEmojiCount = 20

    @Published private(set) var mode: LauncherMode = .root
    @Published private(set) var query = ""
    @Published var selection = 0
    @Published private(set) var rootResults: [RootItem] = []
    @Published private(set) var clips: [ClipItem] = []
    @Published private(set) var emojis: [EmojiEntry] = []
    /// スナップショット撮影中だけ背景を不透明にする（ぼかしはプロセス内描画に写らないため）
    @Published var snapshotMode = false

    /// 開いた直後の検索語が空のルートだけ検索欄のみ（Compact）。それ以外は候補リストまで伸ばす
    var expanded: Bool { mode != .root || !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var onExpandedChange: ((Bool) -> Void)?
    var onModeChange: ((LauncherMode) -> Void)?
    /// 検索欄の文字列を外から書き換える（モード切り替え・リセット時）
    var setFieldText: ((String) -> Void)?

    let index: AppIndex
    let usage: UsageStore
    let clipStore: ClipboardStore
    let allEmojis: [EmojiEntry]

    init(index: AppIndex, usage: UsageStore, clipStore: ClipboardStore, allEmojis: [EmojiEntry]) {
        self.index = index
        self.usage = usage
        self.clipStore = clipStore
        self.allEmojis = allEmojis
    }

    var itemCount: Int {
        switch mode {
        case .root: return rootResults.count
        case .clipboard: return clips.count
        case .emoji: return emojis.count
        }
    }

    func reset(to mode: LauncherMode) {
        let wasExpanded = expanded
        self.mode = mode
        query = ""
        setFieldText?("")
        refresh()
        onModeChange?(mode)
        if wasExpanded != expanded { onExpandedChange?(expanded) }
    }

    func setQuery(_ q: String) {
        let wasExpanded = expanded
        query = q
        refresh()
        if wasExpanded != expanded { onExpandedChange?(expanded) }
    }

    func refresh() {
        selection = 0
        switch mode {
        case .root:
            let items = index.all
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let inputs = items.map { RankInput(id: $0.id, keys: $0.keys, alias: $0.alias, usage: usage.usage($0.id)) }
            rootResults = Ranker.rank(query: query, items: inputs, now: Date()).compactMap { byID[$0] }
        case .clipboard:
            clips = clipStore.list(query: query)
        case .emoji:
            var usageByEmoji: [String: Usage] = [:]
            for e in allEmojis { if let u = usage.usage("emoji:\(e.e)") { usageByEmoji[e.e] = u } }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                // 最近使ったものを先頭に、残りは標準の並び
                let recent = usageByEmoji.sorted { Frecency.value($0.value, now: Date()) > Frecency.value($1.value, now: Date()) }
                    .prefix(Self.recentEmojiCount).map(\.key)
                let recentSet = Set(recent)
                let byChar = Dictionary(allEmojis.map { ($0.e, $0) }, uniquingKeysWith: { a, _ in a })
                emojis = recent.compactMap { byChar[$0] } + allEmojis.filter { !recentSet.contains($0.e) }
            } else {
                emojis = EmojiSearch.search(query, in: allEmojis, usage: usageByEmoji)
            }
        }
    }

    func move(_ delta: Int) {
        guard itemCount > 0 else { return }
        selection = min(max(0, selection + delta), itemCount - 1)
    }

    /// ↑↓。絵文字のグリッドでは 1 行ぶん動く
    func moveVertical(_ direction: Int) {
        move(mode == .emoji ? direction * Self.emojiColumns : direction)
    }
}
