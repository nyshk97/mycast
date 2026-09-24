import AppKit
import Carbon

/// SystemAction の実行。再起動・シャットダウン・スリープは loginwindow への Apple Event（Apple QA1134）。
/// メニューの「再起動…」と同じく各アプリに終了を頼むので、未保存の書類があればそのアプリが止める
enum SystemActions {
    static func perform(_ action: SystemAction) {
        switch action {
        case .sleep: sendToLoginWindow(AEEventID(kAESleep), action)
        case .restart: sendToLoginWindow(AEEventID(kAERestart), action)
        case .shutDown: sendToLoginWindow(AEEventID(kAEShutDown), action)
        case .lockScreen: lockScreen()
        case .quitAllApps: quitAllApps()
        }
    }

    private static func sendToLoginWindow(_ eventID: AEEventID, _ action: SystemAction) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        // .noReply だと拒否（-1743）が catch に来ないので、送る前に許可を確かめる（初回はここでダイアログが出る）
        if let desc = target.aeDesc {
            let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true)
            guard status == noErr else {
                Log.write("system.failed \(action.rawValue) permission=\(status)")
                return
            }
        } else {
            Log.write("system.permission_unchecked \(action.rawValue) no_aedesc")
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        do {
            try event.sendEvent(options: [.noReply], timeout: 10)
            Log.write("system.sent \(action.rawValue)")
        } catch {
            Log.write("system.failed \(action.rawValue) \(error)")
        }
    }

    /// login.framework（非公開）の SACLockScreenImmediate。見つからなければ ⌃⌘Q を合成する
    private static func lockScreen() {
        typealias Fn = @convention(c) () -> Int32
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            let r = unsafeBitCast(sym, to: Fn.self)()
            Log.write("system.sent lockScreen result=\(r)")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: down)
            e?.flags = [.maskControl, .maskCommand]
            e?.post(tap: .cghidEventTap)
        }
        Log.write("system.sent lockScreen fallback=ctrl_cmd_q")
    }

    private static func quitAllApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        let targets = NSWorkspace.shared.runningApplications.filter {
            QuitAllPolicy.shouldQuit(bundleID: $0.bundleIdentifier, isRegular: $0.activationPolicy == .regular,
                                     isSelf: $0.processIdentifier == me)
        }
        let failed = targets.filter { !$0.terminate() }
        Log.write("system.quit_all count=\(targets.count) apps=\(targets.compactMap(\.localizedName)) failed=\(failed.compactMap(\.localizedName))")
    }
}
