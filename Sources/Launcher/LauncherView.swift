import AppKit
import SwiftUI

enum LauncherLayout {
    static let width: CGFloat = 750
    static let barHeight: CGFloat = 58
    static let footerHeight: CGFloat = 34
    static let bodyHeight: CGFloat = 380
    static var expandedHeight: CGFloat { barHeight + 1 + bodyHeight + 1 + footerHeight }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    /// 行のクリックで実行する
    var onActivate: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if model.mode != .root {
                    Text(model.mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.secondary)
                }
                SearchField(model: model)
            }
            .padding(.horizontal, 18)
            .frame(height: LauncherLayout.barHeight)

            if model.expanded {
                Divider().opacity(0.5)
                Group {
                    switch model.mode {
                    case .root: RootListView(model: model, onActivate: onActivate)
                    case .clipboard: ClipboardView(model: model, onActivate: onActivate)
                    case .emoji: EmojiGridView(model: model, onActivate: onActivate)
                    }
                }
                .frame(height: LauncherLayout.bodyHeight)
                Divider().opacity(0.5)
                FooterView(model: model)
                    .frame(height: LauncherLayout.footerHeight)
            }
        }
        .frame(width: LauncherLayout.width,
               height: model.expanded ? LauncherLayout.expandedHeight : LauncherLayout.barHeight,
               alignment: .top)
        .background(model.snapshotMode ? Color(white: 0.13) : Color.clear)
    }
}

// MARK: - 検索欄

/// IME の制御と、キー操作をパネル側で拾うために AppKit の NSTextField を使う
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: LauncherModel

    func makeNSView(context: Context) -> LauncherTextField {
        let f = LauncherTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 21, weight: .regular)
        f.textColor = .labelColor
        f.cell?.usesSingleLineMode = true
        f.cell?.lineBreakMode = .byTruncatingTail
        f.delegate = context.coordinator
        f.placeholderString = model.mode.placeholder
        model.setFieldText = { [weak f] text in
            if f?.stringValue != text { f?.stringValue = text }
        }
        LauncherTextField.current = f
        return f
    }

    func updateNSView(_ f: LauncherTextField, context: Context) {
        f.placeholderString = model.mode.placeholder
        if f.stringValue != model.query, f.currentEditor()?.hasMarkedTextSafe != true {
            f.stringValue = model.query
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: LauncherModel
        init(model: LauncherModel) { self.model = model }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            model.setQuery(f.stringValue)
        }
    }
}

final class LauncherTextField: NSTextField {
    static weak var current: LauncherTextField?
    /// ルート検索ではローマ字入力だけを許す（ABC への切り替えが遅れても 1 打目から英字になる）
    var romanOnly = true {
        didSet { applyInputPolicy() }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        applyInputPolicy()
        return ok
    }

    func applyInputPolicy() {
        guard let editor = currentEditor() as? NSTextView, let ctx = editor.inputContext else { return }
        ctx.allowedInputSourceLocales = romanOnly ? [NSAllRomanInputSourcesLocaleIdentifier] : nil
    }
}

extension NSText {
    var hasMarkedTextSafe: Bool { (self as? NSTextView)?.hasMarkedText() ?? false }
}

// MARK: - ルート検索

struct RootListView: View {
    @ObservedObject var model: LauncherModel
    var onActivate: (Int) -> Void

    var body: some View {
        if model.rootResults.isEmpty {
            EmptyStateView(text: "一致するアプリ・設定がありません")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        SectionHeader(text: "Results")
                        ForEach(Array(model.rootResults.enumerated()), id: \.element.id) { i, item in
                            RootRow(item: item, selected: i == model.selection)
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = i; onActivate(i) }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .onChange(of: model.selection) { _, s in proxy.scrollTo(s) }
            }
        }
    }
}

struct RootRow: View {
    let item: RootItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(iconPath: item.iconPath, symbolName: item.symbolName)
            Text(item.title).font(.system(size: 14)).lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let alias = item.alias {
                Text(alias)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.6)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.typeLabel).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white.opacity(0.12) : Color.clear))
    }
}

struct ItemIcon: View {
    let iconPath: String?
    let symbolName: String?

    var body: some View {
        Group {
            if let iconPath {
                Image(nsImage: IconCache.shared.icon(path: iconPath)).resizable()
            } else if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct SectionHeader: View {
    let text: String
    var body: some View {
        HStack {
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
    }
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        VStack { Spacer(); Text(text).foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - フッター

struct FooterView: View {
    @ObservedObject var model: LauncherModel

    var body: some View {
        HStack(spacing: 14) {
            switch model.mode {
            case .root:
                KeyHint(key: "↵", label: "開く")
            case .clipboard, .emoji:
                KeyHint(key: "↵", label: "貼り付け")
                KeyHint(key: "⌘↵", label: "コピー")
                if model.mode == .emoji, model.emojis.indices.contains(model.selection) {
                    let e = model.emojis[model.selection]
                    Text("\(e.e)  \(e.j ?? e.n)").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(Env.versionLabel).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }
}

struct KeyHint: View {
    let key: String
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
            Text(label).font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }
}
