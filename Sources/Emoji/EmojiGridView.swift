import SwiftUI

struct EmojiGridView: View {
    @ObservedObject var model: LauncherModel
    var onActivate: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: LauncherModel.emojiColumns)

    var body: some View {
        if model.emojis.isEmpty {
            EmptyStateView(text: "一致する絵文字がありません")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(model.emojis.enumerated()), id: \.offset) { i, entry in
                            Text(entry.e)
                                .font(.system(size: 34))
                                .frame(maxWidth: .infinity)
                                .frame(height: 60)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(i == model.selection ? Color.white.opacity(0.16) : Color.white.opacity(0.03)))
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = i; onActivate(i) }
                                .help(entry.j ?? entry.n)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: model.selection) { _, s in proxy.scrollTo(s) }
            }
        }
    }
}

/// 同梱の絵文字データ（Sources/Resources/emoji.json）
enum EmojiData {
    static func load() -> [EmojiEntry] {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([EmojiEntry].self, from: data) else {
            Log.write("emoji.load_failed")
            return []
        }
        return entries
    }
}
