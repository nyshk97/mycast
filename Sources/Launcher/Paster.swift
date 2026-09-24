import AppKit
import ApplicationServices
import Carbon

/// クリップボード履歴と絵文字で共通の「前面アプリに貼り付け」。
///
/// 順序は固定（取りこぼし防止）: パネルを閉じる（呼び出し側。元アプリへの復帰は含めない）→ 入力ソースを復元（同）
/// → 元アプリを 1 回だけ前面化して完了を待つ → ペーストボードに書く → ⌘V を合成。
/// アクセシビリティ未許可・Secure Event Input 有効のときは「コピーだけ」に落として知らせる。
final class Paster {
    enum Content {
        case text(String)
        case image(URL)
        case files([URL])
    }

    private let monitor: ClipboardMonitor
    private var promptedAccessibility = false

    init(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    /// ペーストボードに書くだけ（⌘Enter の経路）
    func copy(_ content: Content) {
        write(content)
    }

    func paste(_ content: Content, into app: NSRunningApplication?) {
        if let app, !app.isTerminated {
            app.activate()
            waitUntilActive(app, deadline: Date().addingTimeInterval(1.0)) { [weak self] active in
                self?.finishPaste(content, appActive: active, appName: app.localizedName)
            }
        } else {
            finishPaste(content, appActive: false, appName: nil)
        }
    }

    private func waitUntilActive(_ app: NSRunningApplication, deadline: Date, done: @escaping (Bool) -> Void) {
        if app.isActive {
            // 前面化の直後はキーウィンドウの切り替えが追いつかないことがあるので少し置く
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { done(true) }
            return
        }
        if Date() > deadline {
            done(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.waitUntilActive(app, deadline: deadline, done: done)
        }
    }

    private func finishPaste(_ content: Content, appActive: Bool, appName: String?) {
        write(content)
        guard appActive else {
            Log.write("paste.fallback_copy reason=app_not_active app=\(appName ?? "-")")
            // ウィンドウの無いまま mycast がアクティブに残ると次の打鍵が捨てられるので手放す
            // （hide だと後から出すトーストまで隠れるので deactivate）
            NSApp.deactivate()
            Toast.show("コピーしました（貼り付け先のアプリを前面にできませんでした）")
            return
        }
        if !AXIsProcessTrusted() {
            Log.write("paste.fallback_copy reason=no_accessibility")
            if !promptedAccessibility {
                promptedAccessibility = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            Toast.show("コピーしました（アクセシビリティの許可が無いため貼り付けできません）")
            return
        }
        if IsSecureEventInputEnabled() {
            Log.write("paste.fallback_copy reason=secure_input")
            Toast.show("コピーしました（パスワード入力中のため貼り付けできません）")
            return
        }
        Self.postCommandV()
        Log.write("paste.posted app=\(appName ?? "-")")
    }

    private func write(_ content: Content) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image(let url):
            if let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .files(let urls):
            pb.writeObjects(urls as [NSURL])
        }
        monitor.markOwnWrite()
    }

    /// 押下中の修飾キー（⌘Enter の ⌘ 等）が混ざらないよう、独立したイベントソースで ⌘V を送る。
    /// 修飾キーは flagsChanged で上げ下げする（keyDown に flags を付けるだけだと素の v が漏れるアプリがある）
    static func postCommandV() {
        let src = CGEventSource(stateID: .privateState)
        let cmd = CGKeyCode(kVK_Command)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmd, keyDown: false) else { return }
        cmdDown.type = .flagsChanged
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.type = .flagsChanged
        cmdUp.flags = []
        for e in [cmdDown, vDown, vUp, cmdUp] {
            e.post(tap: .cgSessionEventTap)
        }
    }
}

/// 画面下に数秒だけ出る通知。パネルを閉じた後の「コピーだけになった」を知らせる
enum Toast {
    private static var window: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 32, height: 36)
        let panel = window ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            return p
        }()
        window = panel
        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 16, y: (size.height - label.frame.height) / 2)
        bg.addSubview(label)
        panel.contentView = bg
        panel.appearance = NSAppearance(named: .darkAqua)
        if let screen = NSScreen.screens.first {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 80, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
