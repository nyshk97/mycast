import AppKit
import ServiceManagement
#if !DEBUG
import Sparkle
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var db: Database!
    private var launcher: LauncherController!
    private var menuBar: MenuBarController!
    private var clipboardMonitor: ClipboardMonitor!
    private var index: AppIndex!
    /// 登録に失敗したホットキーの表示名（メニューバーに出す）
    private(set) var failedHotKeys: [String] = []

    #if !DEBUG
    private var updaterController: SPUStandardUpdaterController?
    #endif

    /// dev 版の検証フック（`--show` 等）を既存インスタンスへ渡す通知名
    static let commandNotification = Notification.Name((Bundle.main.bundleIdentifier ?? "mycast") + ".command")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }
        if forwardToRunningInstance(args) { return }
        Log.write("launch pid=\(ProcessInfo.processInfo.processIdentifier) version=\(Env.version) dev=\(Env.isDev) data=\(Env.dataDir.path)")

        do {
            db = try Database(url: Env.databaseURL)
        } catch {
            Log.write("db.open_failed \(error)")
            let alert = NSAlert()
            alert.messageText = "データベースを開けませんでした"
            alert.informativeText = "\(Env.databaseURL.path)\n\n\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let usage = UsageStore(db: db)
        index = AppIndex(db: db)
        index.startQuery()
        let clipStore = ClipboardStore(db: db, imagesDir: Env.imagesDir)
        clipboardMonitor = ClipboardMonitor(store: clipStore)
        clipboardMonitor.start()
        let paster = Paster(monitor: clipboardMonitor)
        let emojis = EmojiData.load()
        Log.write("emoji.loaded count=\(emojis.count)")
        let model = LauncherModel(index: index, usage: usage, clipStore: clipStore, allEmojis: emojis)
        launcher = LauncherController(model: model, paster: paster)

        registerHotKeys()
        menuBar = MenuBarController(app: self)

        #if !DEBUG
        startUpdater()
        registerLoginItem()
        #endif

        #if DEBUG
        DistributedNotificationCenter.default().addObserver(
            forName: Self.commandNotification, object: nil, queue: .main
        ) { [weak self] note in
            let args = (note.object as? String).flatMap { $0.isEmpty ? nil : $0.components(separatedBy: "\u{1F}") } ?? []
            self?.runHookCommands(args)
        }
        if !args.isEmpty { runHookCommands(args) }
        #endif
    }

    // MARK: - 単一インスタンス

    /// 既に動いているインスタンスがあれば、引数を渡して自分は終了する。渡したら true
    private func forwardToRunningInstance(_ args: [String]) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return false }
        Log.write("launch.forward_to_running pid=\(others.map(\.processIdentifier)) args=\(args)")
        #if DEBUG
        if !args.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.commandNotification, object: args.joined(separator: "\u{1F}"), userInfo: nil, deliverImmediately: true)
        }
        #endif
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }

    // MARK: - ホットキー

    private func registerHotKeys() {
        let launcherBinding = HotKeyBindings.launcher
        let emojiBinding = HotKeyBindings.emoji
        let pairs: [(HotKeyBindings.Binding, () -> Void)] = [
            (launcherBinding, { [weak self] in self?.launcher.toggleLauncher() }),
            (emojiBinding, { [weak self] in self?.launcher.toggleEmoji() }),
        ]
        for (binding, handler) in pairs {
            let status = HotKeyCenter.shared.register(keyCode: binding.keyCode, modifiers: binding.modifiers, handler: handler)
            if status == noErr {
                Log.write("hotkey.registered \(binding.label)")
            } else {
                failedHotKeys.append(binding.label)
                Log.write("hotkey.register_failed \(binding.label) status=\(status)")
            }
        }
        if !failedHotKeys.isEmpty {
            // 起動直後はこちらで気づかせ、以後はメニューバーのアイコンで気づけるようにする
            let alert = NSAlert()
            alert.messageText = "ホットキーを登録できませんでした"
            alert.informativeText = "\(failedHotKeys.joined(separator: " / ")) は他のアプリ（Raycast 等）が使っている可能性があります。そのアプリを終了してから mycast を起動し直してください。"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - メニューから呼ぶ

    func openLauncher() {
        launcher.show(.root, direct: false)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "Version \(Env.version)",
            .version: "",
        ])
    }

    #if !DEBUG
    var canCheckForUpdates: Bool { updaterController != nil }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// SUPublicEDKey が未設定のまま Sparkle を起動すると起動時にエラーダイアログが出るので、そのときは起動しない
    private func startUpdater() {
        let key = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("__") else {
            Log.write("update.disabled reason=no_public_key")
            return
        }
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        Log.write("update.started")
    }

    /// 常用版は初回起動時にログイン項目へ登録する
    private func registerLoginItem() {
        switch SMAppService.mainApp.status {
        case .enabled:
            break
        case .requiresApproval:
            Log.write("login_item.requires_approval")
        default:
            do {
                try SMAppService.mainApp.register()
                Log.write("login_item.registered")
            } catch {
                Log.write("login_item.register_failed \(error)")
            }
        }
    }
    #endif

    // MARK: - 検証フック（dev 版のみ）

    #if DEBUG
    /// `--show root|clipboard|emoji` / `--query <文字列>` / `--key down|up|left|right|escape` /
    /// `--snapshot <png>` / `--hide`。実行（Enter）のフックは作らない（他のアプリに貼り付けてしまうため）。
    /// `--show` はフォーカスも入力ソースも奪わない（作業中のユーザーの邪魔をしない）
    private func runHookCommands(_ args: [String]) {
        var queue = args
        func next() {
            guard !queue.isEmpty else { return }
            let cmd = queue.removeFirst()
            switch cmd {
            case "--show":
                let mode = LauncherMode(rawValue: queue.first ?? "") ?? .root
                if LauncherMode(rawValue: queue.first ?? "") != nil { queue.removeFirst() }
                launcher.show(mode, direct: false, activate: false)
                next()
            case "--query":
                let q = queue.isEmpty ? "" : queue.removeFirst()
                launcher.typeQuery(q)
                next()
            case "--key":
                let k = queue.isEmpty ? "" : queue.removeFirst()
                launcher.pressKey(k)
                next()
            case "--snapshot":
                let path = queue.isEmpty ? "/tmp/mycast-snapshot.png" : queue.removeFirst()
                launcher.snapshot(to: path) { next() }
            case "--hide":
                launcher.close(.lostFocus)
                next()
            case "--dump":
                let m = launcher.model
                let items: [String]
                switch m.mode {
                case .root: items = m.rootResults.prefix(10).map { "\($0.title) [\($0.typeLabel)]" }
                case .clipboard: items = m.clips.prefix(10).map { "\($0.kind.rawValue): \($0.title)" }
                case .emoji: items = m.emojis.prefix(10).map { $0.e }
                }
                Log.write("hook.dump mode=\(m.mode.rawValue) query=\(m.query) selection=\(m.selection) count=\(m.itemCount) expanded=\(m.expanded) items=\(items)")
                next()
            default:
                Log.write("hook.unknown \(cmd)")
                next()
            }
        }
        next()
    }
    #endif
}
