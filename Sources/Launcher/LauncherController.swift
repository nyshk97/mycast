import AppKit
import Carbon
import SwiftUI

/// key になれるボーダーレスのパネル。フォーカスを失ったら閉じる
final class LauncherPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// パネルの開閉・キー操作・実行。
///
/// フォーカスは Raycast と同じモデル: ホットキーで前面アプリを記憶 → 自アプリをアクティブ化 → key な NSPanel を表示
/// → 閉じるときに、Esc / ホットキー再押下 / コピーで閉じたときだけ記憶したアプリへ戻す
/// （他アプリのクリックで key を奪われて閉じたときは、そのアプリを前面のままにする）
final class LauncherController {
    enum CloseReason: String {
        /// Esc
        case escape
        /// ホットキーの再押下
        case toggle
        /// ⌘Enter でコピーだけした・計算の答えをコピーした
        case copied
        /// アプリ・設定パネルを開いた（開いた側が前面になる）
        case launched
        /// 貼り付け（前面化は Paster が明示的に 1 回だけ行う）
        case paste
        /// 他のアプリがクリックされた等で key を失った
        case lostFocus
        /// スリープ・画面ロック（復帰後は元のアプリで作業を続けるので戻す）
        case suspended
    }

    let model: LauncherModel
    private let paster: Paster
    private let panel: LauncherPanel
    private var hosting: NSHostingView<LauncherView>?
    private let effect = NSVisualEffectView()
    private var previousApp: NSRunningApplication?
    private var savedInputSource: TISInputSource?
    /// ⌃⌘Space で絵文字を直接開いたとき true（Esc でルートに戻らず閉じる）
    private var openedDirectly = false
    private var closing = false
    private var keyMonitor: Any?
    /// 検証フックの Enter で本物の再起動等を撃たないためのフラグ（dev のフックだけが立てる）
    private var systemDryRun = false

    var isShown: Bool { panel.isVisible }
    /// Update mycast の実行先（Sparkle は AppDelegate が持つ）
    var onCheckForUpdates: (() -> Void)?

    init(model: LauncherModel, paster: Paster) {
        self.model = model
        self.paster = paster
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.barHeight),
            styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        // 背景のぼかし。黒ガラスの面と縁は SwiftUI 側（LauncherView）で描き、ここは角丸を合わせるだけ
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.maskImage = Self.roundedMask(radius: LauncherLayout.collapsedRadius)
        panel.contentView = effect

        let host = NSHostingView(rootView: LauncherView(model: model, onActivate: { [weak self] i in
            self?.model.selection = i
            self?.execute(copyOnly: false)
        }))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = effect.bounds
        effect.addSubview(host)
        hosting = host

        panel.onResignKey = { [weak self] in
            guard let self, !self.closing, self.panel.isVisible else { return }
            self.close(.lostFocus)
        }
        model.onExpandedChange = { [weak self] _ in self?.layoutPanel() }
        model.onModeChange = { [weak self] mode in
            LauncherTextField.current?.romanOnly = (mode == .root)
            self?.layoutPanel()
        }
        installKeyMonitor()
    }

    // MARK: - ホットキー

    func toggleLauncher() {
        if isShown { close(.toggle) } else { show(.root, direct: false) }
    }

    func toggleEmoji() {
        if isShown, model.mode == .emoji {
            close(.toggle)
        } else if isShown {
            openedDirectly = true
            model.reset(to: .emoji)
        } else {
            show(.emoji, direct: true)
        }
    }

    // MARK: - 開閉

    func show(_ mode: LauncherMode, direct: Bool, activate: Bool = true) {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        openedDirectly = direct
        model.reset(to: mode) // Pop to Root: 開くたびに空・指定のモードから
        layoutPanel()
        hosting?.layoutSubtreeIfNeeded() // 検索欄（NSViewRepresentable）の生成を確定させる
        if activate {
            // 表示中に呼ばれても ABC を「元の入力ソース」として上書きしない
            if savedInputSource == nil { savedInputSource = InputSource.current() }
            InputSource.selectABC()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            focusField()
        } else {
            // dev の検証フック用: フォーカスも入力ソースも奪わずに表示だけする
            panel.orderFrontRegardless()
        }
        Log.write("panel.shown mode=\(mode.rawValue) direct=\(direct) activate=\(activate) prev=\(previousApp?.bundleIdentifier ?? "-")")
    }

    func close(_ reason: CloseReason) {
        guard panel.isVisible else { return }
        closing = true
        panel.orderOut(nil)
        closing = false
        if let s = savedInputSource {
            InputSource.select(s)
            savedInputSource = nil
        }
        switch reason {
        case .escape, .toggle, .copied, .suspended:
            restorePreviousApp()
        case .launched, .paste, .lostFocus:
            break
        }
        Log.write("panel.closed reason=\(reason.rawValue)")
    }

    private func restorePreviousApp() {
        if let app = previousApp, !app.isTerminated {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
    }

    private func focusField() {
        if let field = LauncherTextField.current {
            field.romanOnly = (model.mode == .root)
            panel.makeFirstResponder(field)
        }
        // 開いた直後に key になりきらず入力を取りこぼすことがあるので、次のループでもう一度（検索欄も取り直す）
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if !self.panel.isKeyWindow { self.panel.makeKeyAndOrderFront(nil) }
            guard let field = LauncherTextField.current else {
                Log.write("panel.focus_failed no_field")
                return
            }
            field.romanOnly = (self.model.mode == .root)
            if field.currentEditor() == nil { self.panel.makeFirstResponder(field) }
        }
    }

    /// 主画面（メニューバーのある画面）の上 1/5 あたりに中央寄せ。高さが変わっても上端を固定する
    private func layoutPanel() {
        guard let screen = NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let height = model.expanded ? LauncherLayout.expandedHeight : LauncherLayout.barHeight
        let top = vf.maxY - vf.height * 0.2
        let frame = NSRect(x: (vf.midX - LauncherLayout.width / 2).rounded(), y: (top - height).rounded(),
                           width: LauncherLayout.width, height: height)
        effect.maskImage = Self.roundedMask(radius: model.expanded ? LauncherLayout.expandedRadius : LauncherLayout.collapsedRadius)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// behindWindow のぼかしは layer の角丸では切れず、角に四角いぼかしが残る。maskImage で切る
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - キー操作

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// 処理したら true（イベントを捨てる）
    private func handleKey(_ event: NSEvent) -> Bool {
        // 変換中の文字があるときは IME に任せる
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Escape:
            handleEscape()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            execute(copyOnly: flags.contains(.command))
            return true
        case kVK_DownArrow:
            model.moveVertical(1)
            return true
        case kVK_UpArrow:
            model.moveVertical(-1)
            return true
        case kVK_LeftArrow where model.mode == .emoji:
            model.move(-1)
            return true
        case kVK_RightArrow where model.mode == .emoji:
            model.move(1)
            return true
        case kVK_ANSI_N where flags == .control:
            model.moveVertical(1)
            return true
        case kVK_ANSI_P where flags == .control:
            model.moveVertical(-1)
            return true
        case kVK_ANSI_B where flags == .control && model.mode == .emoji:
            model.move(-1)
            return true
        case kVK_ANSI_F where flags == .control && model.mode == .emoji:
            model.move(1)
            return true
        default:
            return false
        }
    }

    /// 検索語があれば消す → サブ画面ならルートへ戻る（ホットキーで直接開いたときは閉じる）→ ルートなら閉じる
    private func handleEscape() {
        if !model.query.isEmpty {
            model.setFieldText?("")
            model.setQuery("")
        } else if model.mode != .root, !openedDirectly {
            model.reset(to: .root)
        } else {
            close(.escape)
        }
    }

    // MARK: - 実行

    func execute(copyOnly: Bool) {
        switch model.mode {
        case .root:
            if model.calcSelected, let calc = model.calc {
                // Raycast と同じく Enter でも答えをコピーするだけ（貼り付けない）
                paster.copy(.text(calc.answer))
                close(.copied)
                Log.write("calc.copied")
                return
            }
            guard let item = model.selectedRootItem else { return }
            if case .system(let action) = item.kind {
                // ⌘Enter は他の画面では「コピーして戻る」なので、システム操作の確定には使わない
                if copyOnly { return }
                if action.needsConfirmation, model.armedAction != action {
                    model.armedAction = action
                    Log.write("system.armed \(action.rawValue)")
                    return
                }
            }
            // 検証フックの dry run では履歴を書かない（以後の並びが検証のせいで変わる）
            if !systemDryRun { model.usage.record(item.id) }
            switch item.kind {
            case .app(let url):
                close(.launched)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    if let error { Log.write("launch.failed \(url.path) \(error)") }
                }
                Log.write("launch.app \(url.lastPathComponent)")
            case .settingsPane(let id):
                close(.launched)
                if let url = URL(string: "x-apple.systempreferences:\(id)") {
                    NSWorkspace.shared.open(url)
                }
                Log.write("launch.pane \(id)")
            case .system(let action):
                model.armedAction = nil
                // dry run では元のアプリを前面化しない（検証フックはフォーカスに触らない）
                close(action.returnsToPreviousApp && !systemDryRun ? .suspended : .launched)
                if systemDryRun {
                    Log.write("system.dry_run \(action.rawValue)")
                } else {
                    SystemActions.perform(action)
                }
            case .checkForUpdates:
                // Sparkle のウインドウが前面に出るので元のアプリへは戻さない
                close(.launched)
                onCheckForUpdates?()
                Log.write("update.check_from_launcher")
            case .command(let mode):
                openedDirectly = false
                model.reset(to: mode)
                focusField()
            }
        case .clipboard:
            guard model.clips.indices.contains(model.selection) else { return }
            let item = model.clips[model.selection]
            let content: Paster.Content
            switch item.kind {
            case .text: content = .text(item.text ?? "")
            case .file: content = .files(item.fileURLs)
            case .image:
                guard let url = model.clipStore.imageURL(item) else { return }
                content = .image(url)
            }
            model.clipStore.bump(id: item.id)
            deliver(content, copyOnly: copyOnly)
        case .emoji:
            guard model.emojis.indices.contains(model.selection) else { return }
            let entry = model.emojis[model.selection]
            model.usage.record("emoji:\(entry.e)")
            deliver(.text(entry.e), copyOnly: copyOnly)
        }
    }

    private func deliver(_ content: Paster.Content, copyOnly: Bool) {
        if copyOnly {
            paster.copy(content)
            close(.copied)
            Log.write("deliver.copied mode=\(model.mode.rawValue)")
        } else {
            let target = previousApp
            close(.paste)
            paster.paste(content, into: target)
        }
    }

    // MARK: - 検証フック（dev 版のみ呼ばれる）

    /// パネルの中身を PNG に保存する。画面収録許可が要らないプロセス内描画。
    /// 背景ぼかしは写らないので、撮影中だけ不透明な背景にする（レイアウト確認用）
    func snapshot(to path: String, completion: @escaping () -> Void) {
        model.snapshotMode = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let view = self.panel.contentView else { completion(); return }
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    do {
                        try png.write(to: URL(fileURLWithPath: path))
                        Log.write("snapshot.saved \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                    } catch {
                        Log.write("snapshot.failed \(error)")
                    }
                }
            }
            self.model.snapshotMode = false
            completion()
        }
    }

    func typeQuery(_ q: String) {
        model.setFieldText?(q)
        model.setQuery(q)
    }

    func pressKey(_ name: String) {
        switch name {
        case "down": model.moveVertical(1)
        case "up": model.moveVertical(-1)
        case "left": model.move(-1)
        case "right": model.move(1)
        case "escape": handleEscape()
        case "enter":
            // システム操作だけ受け付け、実行は dry run にする（貼り付け・起動は他のアプリに作用するので撃たない）
            guard isShown, case .system = model.selectedRootItem?.kind else {
                Log.write("hook.enter_refused not_system")
                return
            }
            systemDryRun = true
            execute(copyOnly: false)
            systemDryRun = false
        default: Log.write("hook.unknown_key \(name)")
        }
    }
}
