import AppKit

/// メニューバー常駐 UI。項目は About / アップデートを確認 / 終了 だけ（設定画面は作らない）
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let app: AppDelegate
    private let statusItem: NSStatusItem

    init(app: AppDelegate) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild(menu)

        let warn = !app.failedHotKeys.isEmpty
        if warn {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "mycast")
            image?.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = StatusIcon.make()
        }
        Log.write("menu.installed")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "mycast を開く（\(HotKeyBindings.launcher.label)）", action: #selector(openLauncher(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if !app.failedHotKeys.isEmpty {
            let warn = NSMenuItem(title: "⚠︎ ホットキーを登録できませんでした: \(app.failedHotKeys.joined(separator: " / "))", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        let version = NSMenuItem(title: Env.versionLabel, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let about = NSMenuItem(title: "mycast について", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        #if !DEBUG
        let update = NSMenuItem(title: "アップデートを確認…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        update.target = self
        update.isEnabled = app.canCheckForUpdates
        menu.addItem(update)
        #endif
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "終了", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openLauncher(_ sender: Any?) { app.openLauncher() }
    @objc private func showAbout(_ sender: Any?) { app.showAbout() }
    #if !DEBUG
    @objc private func checkForUpdates(_ sender: Any?) { app.checkForUpdates() }
    #endif
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}
