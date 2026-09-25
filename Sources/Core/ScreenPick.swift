import CoreGraphics

/// パネルを出す画面の選択（純粋関数）
enum ScreenPick {
    /// `point` を含む画面の添字。どれにも入らなければ 0（主画面）。
    /// 右端・上端ちょうども含める（`NSEvent.mouseLocation` は画面最上端で y == maxY になり、`CGRect.contains` だと外れる）
    static func index(containing point: CGPoint, in frames: [CGRect]) -> Int {
        frames.firstIndex { f in
            point.x >= f.minX && point.x <= f.maxX && point.y >= f.minY && point.y <= f.maxY
        } ?? 0
    }
}
