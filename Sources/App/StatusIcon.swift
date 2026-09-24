import AppKit

/// メニューバーのアイコン。アプリアイコンと同じ「検索ピル＋3 つの点＋キャレット」を、
/// 塗りつぶしたピルから点とキャレットを抜いた形のテンプレート画像にする（明暗はシステムが合わせる）
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath(roundedRect: NSRect(x: 1, y: 5, width: 16, height: 8), xRadius: 4, yRadius: 4)
            for cx in [4.6, 7.2, 9.8] {
                path.appendOval(in: NSRect(x: cx - 1.25, y: 9 - 1.25, width: 2.5, height: 2.5))
            }
            path.appendRoundedRect(NSRect(x: 12.2, y: 7, width: 1.1, height: 4), xRadius: 0.55, yRadius: 0.55)
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "mycast"
        return image
    }
}
