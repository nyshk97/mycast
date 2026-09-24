import Foundation

/// ルート検索から実行するシステム操作（Raycast の System コマンドのうち使うもの）
enum SystemAction: String, CaseIterable {
    case sleep, lockScreen, restart, shutDown, quitAllApps

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .lockScreen: return "Lock Screen"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .quitAllApps: return "Close All Apps"
        }
    }

    var subtitle: String {
        switch self {
        case .sleep: return "スリープ"
        case .lockScreen: return "画面をロック"
        case .restart: return "再起動"
        case .shutDown: return "シャットダウン"
        case .quitAllApps: return "すべてのアプリを終了"
        }
    }

    /// 検索キー。ルートの検索欄は ABC 入力なのでローマ字も入れる（AppPathRules.romanized は漢字をピンインにするので使わない）
    var keys: [String] {
        switch self {
        case .sleep: return ["Sleep", "スリープ", "suripu"]
        case .lockScreen: return ["Lock Screen", "画面をロック", "rokku"]
        case .restart: return ["Restart", "Reboot", "再起動", "saikidou"]
        case .shutDown: return ["Shut Down", "Shutdown", "Power Off", "シャットダウン", "shattodaun"]
        case .quitAllApps: return ["Close All Apps", "Quit All Apps", "すべてのアプリを終了", "subete"]
        }
    }

    var symbolName: String {
        switch self {
        case .sleep: return "moon.fill"
        case .lockScreen: return "lock.fill"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .quitAllApps: return "xmark"
        }
    }

    /// 取り返しのつかない操作は Enter 2 回で実行する（1 回目は確認表示に切り替えるだけ）。
    /// スリープとロックはすぐ戻れるので確認しない
    var needsConfirmation: Bool {
        switch self {
        case .sleep, .lockScreen: return false
        case .restart, .shutDown, .quitAllApps: return true
        }
    }

    /// 閉じたあと元のアプリへ戻すか。スリープ・ロックは復帰後に同じ作業を続けるので戻す
    /// （再起動・シャットダウン・全終了は戻す相手がいなくなる）
    var returnsToPreviousApp: Bool {
        switch self {
        case .sleep, .lockScreen: return true
        case .restart, .shutDown, .quitAllApps: return false
        }
    }

    /// 確認待ちの行に出す文言
    var confirmPrompt: String { "Press ↵ again to \(title)" }
}

/// Close All Apps で閉じるアプリの判定
enum QuitAllPolicy {
    /// 閉じずに残すアプリ（mycast 自身は pid で別に除外する）
    static let keptBundleIDs: Set<String> = ["com.apple.finder"]

    /// Dock に出る普通のアプリ（`activationPolicy == .regular`）のうち、残すもの・自分以外。
    /// mycast は LSUIElement（accessory）なので isRegular で既に外れるが、LSUIElement を外したときの保険に isSelf も見る
    static func shouldQuit(bundleID: String?, isRegular: Bool, isSelf: Bool) -> Bool {
        guard isRegular, !isSelf else { return false }
        if let bundleID, keptBundleIDs.contains(bundleID) { return false }
        return true
    }
}
