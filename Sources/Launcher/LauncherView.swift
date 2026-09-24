import AppKit
import SwiftUI

enum LauncherLayout {
    static let width: CGFloat = 750
    static let barHeight: CGFloat = 60
    static let footerHeight: CGFloat = 34
    static let bodyHeight: CGFloat = 380
    static var expandedHeight: CGFloat { barHeight + 1 + bodyHeight + 1 + footerHeight }
    /// 閉じた状態は完全な丸ピル、候補が出たら角丸のカード
    static let collapsedRadius: CGFloat = barHeight / 2
    static let expandedRadius: CGFloat = 22
    static let queryFontSize: CGFloat = 17
}

/// アプリアイコンと同じ「黒ガラスのピル＋3 色の点＋クリーム色のキャレット」の配色
enum Theme {
    static let cream = Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEC / 255)
    static let creamNS = NSColor(srgbRed: 0xFB / 255, green: 0xF6 / 255, blue: 0xEC / 255, alpha: 1)
    static let blue = Color(red: 0x5D / 255, green: 0x7F / 255, blue: 0xBF / 255)
    static let mustard = Color(red: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255)
    static let rose = Color(red: 0xCF / 255, green: 0x6A / 255, blue: 0x70 / 255)
    static let line = cream.opacity(0.07)
    static let selectedFill = cream.opacity(0.09)
    static let selectedStroke = cream.opacity(0.08)
    static let keyFill = cream.opacity(0.1)

    static func color(for mode: LauncherMode) -> Color {
        switch mode {
        case .root: return blue
        case .clipboard: return mustard
        case .emoji: return rose
        }
    }

    /// 黒ガラスの面。上端の検索欄のあたりだけ少し明るい
    static func glass(opaque: Bool) -> LinearGradient {
        let a = opaque ? 1.0 : 0.92
        return LinearGradient(stops: [
            .init(color: Color(red: 52 / 255, green: 49 / 255, blue: 45 / 255).opacity(a), location: 0),
            .init(color: Color(red: 24 / 255, green: 23 / 255, blue: 21 / 255).opacity(a + 0.02), location: 0.13),
            .init(color: Color(red: 20 / 255, green: 19 / 255, blue: 17 / 255).opacity(a + 0.02), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    /// 行のクリックで実行する
    var onActivate: (Int) -> Void

    private var radius: CGFloat { model.expanded ? LauncherLayout.expandedRadius : LauncherLayout.collapsedRadius }
    private var height: CGFloat { model.expanded ? LauncherLayout.expandedHeight : LauncherLayout.barHeight }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ModeDots(mode: model.mode, lit: model.expanded)
                if model.mode != .root {
                    Text(model.mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.keyFill))
                }
                SearchField(model: model)
            }
            .padding(.horizontal, 20)
            .frame(height: LauncherLayout.barHeight)

            if model.expanded {
                Rectangle().fill(Theme.line).frame(height: 1)
                Group {
                    switch model.mode {
                    case .root: RootListView(model: model, onActivate: onActivate)
                    case .clipboard: ClipboardView(model: model, onActivate: onActivate)
                    case .emoji: EmojiGridView(model: model, onActivate: onActivate)
                    }
                }
                .frame(height: LauncherLayout.bodyHeight)
                Rectangle().fill(Theme.line).frame(height: 1)
                FooterView(model: model)
                    .frame(height: LauncherLayout.footerHeight)
            }
        }
        .foregroundStyle(Theme.cream)
        .frame(width: LauncherLayout.width, height: height, alignment: .top)
        .background(Theme.glass(opaque: model.snapshotMode))
        .overlay(alignment: .top) {
            // 上端の光の反射（ガラスの厚み）
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// アイコンと同じ 3 色の点。今のモードの点だけ光る（閉じた状態では全部控えめ）
struct ModeDots: View {
    let mode: LauncherMode
    let lit: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach([LauncherMode.root, .clipboard, .emoji], id: \.self) { m in
                let on = lit && m == mode
                Circle()
                    .fill(Theme.color(for: m))
                    .frame(width: 9, height: 9)
                    .opacity(on ? 1 : 0.35)
                    .scaleEffect(on ? 1.25 : 1)
                    .shadow(color: on ? Theme.color(for: m).opacity(0.9) : .clear, radius: 5)
                    .animation(.easeOut(duration: 0.2), value: on)
            }
        }
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
        f.font = .systemFont(ofSize: LauncherLayout.queryFontSize, weight: .regular)
        f.textColor = Theme.creamNS
        f.cell?.usesSingleLineMode = true
        f.cell?.lineBreakMode = .byTruncatingTail
        f.delegate = context.coordinator
        f.setPlaceholder(model.mode.placeholder)
        model.setFieldText = { [weak f] text in
            if f?.stringValue != text { f?.stringValue = text }
        }
        LauncherTextField.current = f
        return f
    }

    func updateNSView(_ f: LauncherTextField, context: Context) {
        f.setPlaceholder(model.mode.placeholder)
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

    func setPlaceholder(_ text: String) {
        guard placeholderAttributedString?.string != text else { return }
        placeholderAttributedString = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: LauncherLayout.queryFontSize, weight: .regular),
            .foregroundColor: Theme.creamNS.withAlphaComponent(0.4),
        ])
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        applyInputPolicy()
        (currentEditor() as? NSTextView)?.insertionPointColor = Theme.creamNS
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

// MARK: - 選択の見た目（全画面で共通）

struct SelectionBackground: View {
    let selected: Bool
    var accent: Color?
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(selected ? Theme.selectedFill : Color.clear)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(selected ? Theme.selectedStroke : Color.clear, lineWidth: 1)
            if selected, let accent {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 11)
            }
        }
    }
}

// MARK: - ルート検索

struct RootListView: View {
    @ObservedObject var model: LauncherModel
    var onActivate: (Int) -> Void

    var body: some View {
        if model.rootResults.isEmpty, model.calc == nil {
            EmptyStateView(text: "No results")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if let calc = model.calc {
                            SectionHeader(text: "Calculator")
                            CalcCard(calc: calc, selected: model.selection == 0)
                                .id(0)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = 0; onActivate(0) }
                        }
                        if !model.rootResults.isEmpty {
                            SectionHeader(text: "Results")
                        }
                        ForEach(Array(model.rootResults.enumerated()), id: \.element.id) { i, item in
                            let index = i + model.rootOffset
                            RootRow(item: item, selected: index == model.selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selection = index; onActivate(index) }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                .id(model.generation)
                .onChange(of: model.selection) { _, s in proxy.scrollTo(s) }
            }
        }
    }
}

/// 「式 → 答え」のカード（Raycast の Calculator）
struct CalcCard: View {
    let calc: CalcResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            side(calc.expression, label: "Expression")
            VStack(spacing: 0) {
                Rectangle().fill(Theme.line).frame(width: 1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.6)
                    .padding(.vertical, 6)
                Rectangle().fill(Theme.line).frame(width: 1)
            }
            side(calc.display, label: "Answer")
        }
        .frame(height: 112)
        .background(SelectionBackground(selected: selected, accent: Theme.blue))
    }

    private func side(_ text: String, label: String) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.keyFill))
                .opacity(0.7)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

struct RootRow: View {
    let item: RootItem
    let selected: Bool

    private var accent: Color {
        if case .command(let mode) = item.kind { return Theme.color(for: mode) }
        return Theme.blue
    }

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(iconPath: item.iconPath, symbolName: item.symbolName, tint: accent)
            Text(item.title).font(.system(size: 14)).lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.system(size: 13)).opacity(0.5).lineLimit(1)
            }
            if let alias = item.alias {
                Text(alias)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.cream.opacity(0.35)))
                    .opacity(0.7)
            }
            Spacer()
            Text(item.typeLabel).font(.system(size: 12)).opacity(0.45)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(SelectionBackground(selected: selected, accent: accent))
    }
}

struct ItemIcon: View {
    let iconPath: String?
    let symbolName: String?
    var tint: Color = Theme.blue

    var body: some View {
        Group {
            if let iconPath {
                Image(nsImage: IconCache.shared.icon(path: iconPath)).resizable()
            } else if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0x1F / 255, green: 0x1D / 255, blue: 0x1B / 255))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint))
            }
        }
        .frame(width: 26, height: 26)
    }
}

struct SectionHeader: View {
    let text: String
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .opacity(0.5)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
    }
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        VStack { Spacer(); Text(text).opacity(0.5); Spacer() }
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
                KeyHint(key: "↵", label: model.calcSelected ? "Copy Answer" : "Open")
            case .clipboard, .emoji:
                KeyHint(key: "↵", label: "Paste")
                KeyHint(key: "⌘↵", label: "Copy")
                if model.mode == .emoji, model.emojis.indices.contains(model.selection) {
                    let e = model.emojis[model.selection]
                    Text("\(e.e)  \(e.j ?? e.n)").font(.system(size: 12)).opacity(0.6).lineLimit(1)
                }
            }
            Spacer()
            Text(Env.versionLabel).font(.system(size: 11)).opacity(0.35)
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
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.keyFill))
            Text(label).font(.system(size: 12)).opacity(0.7)
        }
    }
}
