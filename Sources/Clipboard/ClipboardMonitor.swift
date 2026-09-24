import AppKit

/// NSPasteboard.general の changeCount を 0.5 秒ごとに見て、変わったら履歴に記録する
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var purgeTimer: Timer?
    private var lastChangeCount: Int
    var onRecorded: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        store.purge()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.store.purge() }
        Log.write("clipboard.monitor_started")
    }

    /// 自分がペーストボードに書いた後に呼ぶ。その changeCount を既読にして記録しない
    func markOwnWrite() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        capture(pb)
    }

    private func capture(_ pb: NSPasteboard) {
        let types = (pb.types ?? []).map(\.rawValue)
        if ClipboardPolicy.shouldSkip(types: types) {
            Log.write("clipboard.skipped_marked")
            return
        }
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let text = pb.string(forType: .string)
        let hasImage = pb.types?.contains(where: { $0 == .png || $0 == .tiff }) ?? false
        guard let kind = ClipboardPolicy.kind(hasFiles: !fileURLs.isEmpty, text: text, hasImage: hasImage) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        switch kind {
        case .file:
            store.record(kind: .file, text: fileURLs.map(\.path).joined(separator: "\n"), imageData: nil,
                         width: nil, height: nil, sourceApp: source)
        case .text:
            store.record(kind: .text, text: text, imageData: nil, width: nil, height: nil, sourceApp: source)
        case .image:
            guard let (png, w, h) = Self.pngData(pb) else { return }
            store.record(kind: .image, text: nil, imageData: png, width: w, height: h, sourceApp: source)
        }
        Log.write("clipboard.recorded kind=\(kind.rawValue)")
        onRecorded?()
    }

    private static func pngData(_ pb: NSPasteboard) -> (Data, Int, Int)? {
        let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff)
        guard let raw, let rep = NSBitmapImageRep(data: raw) else { return nil }
        let png = pb.data(forType: .png) ?? rep.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }
}
