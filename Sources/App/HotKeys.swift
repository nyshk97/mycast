import Carbon
import Foundation

/// Carbon の RegisterEventHotKey によるグローバルホットキー。アクセシビリティ許可は要らない
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x4D59_4354 // 'MYCT'

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async {
                HotKeyCenter.shared.handlers[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 登録に失敗したら OSStatus を返す（他のアプリが同じ組み合わせを取っている等）
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> OSStatus {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            handlers[id] = handler
        }
        return status
    }
}

/// mycast が使うホットキー（固定）。dev 版は Raycast・常用版と並行できるよう ⌥ を足した別キー
enum HotKeyBindings {
    struct Binding {
        let keyCode: Int
        let modifiers: Int
        let label: String
    }

    #if DEBUG
    static let launcher = Binding(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey, label: "⌃⌥L")
    static let emoji = Binding(keyCode: kVK_Space, modifiers: controlKey | optionKey | cmdKey, label: "⌃⌥⌘Space")
    #else
    static let launcher = Binding(keyCode: kVK_ANSI_L, modifiers: controlKey, label: "⌃L")
    static let emoji = Binding(keyCode: kVK_Space, modifiers: controlKey | cmdKey, label: "⌃⌘Space")
    #endif
}
