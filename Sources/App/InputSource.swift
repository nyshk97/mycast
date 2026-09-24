import Carbon
import Foundation

/// 入力ソース（IME）の保存・切り替え・復元。TISSelectInputSource はシステム全体の入力ソースを変えるので、
/// パネルを閉じたら必ず表示前のものに戻す
enum InputSource {
    static let abcID = "com.apple.keylayout.ABC"

    static func current() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    static func id(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func select(_ source: TISInputSource) {
        TISSelectInputSource(source)
    }

    static func selectABC() {
        let filter = [kTISPropertyInputSourceID as String: abcID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let abc = list.first else {
            Log.write("input_source.abc_not_found")
            return
        }
        TISSelectInputSource(abc)
    }
}
