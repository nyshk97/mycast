import AppKit
import SwiftUI

/// 左に履歴の一覧、右に選択中の内容のプレビュー
struct ClipboardView: View {
    @ObservedObject var model: LauncherModel
    var onActivate: (Int) -> Void

    var body: some View {
        if model.clips.isEmpty {
            EmptyStateView(text: model.query.isEmpty ? "まだ履歴がありません" : "一致する履歴がありません")
        } else {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, item in
                                ClipRow(item: item, selected: i == model.selection, store: model.clipStore)
                                    .id(i)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.selection = i; onActivate(i) }
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .onChange(of: model.selection) { _, s in proxy.scrollTo(s) }
                }
                .frame(width: 300)
                Divider().opacity(0.5)
                if model.clips.indices.contains(model.selection) {
                    ClipPreview(item: model.clips[model.selection], store: model.clipStore)
                } else {
                    Spacer()
                }
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let selected: Bool
    let store: ClipboardStore

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch item.kind {
                case .text:
                    Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
                case .file:
                    if let first = item.fileURLs.first {
                        Image(nsImage: IconCache.shared.icon(path: first.path)).resizable()
                    }
                case .image:
                    if let url = store.imageURL(item), let img = ThumbnailCache.shared.image(url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 20, height: 20)
            Text(item.title).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white.opacity(0.12) : Color.clear))
    }
}

struct ClipPreview: View {
    let item: ClipItem
    let store: ClipboardStore

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch item.kind {
                case .text:
                    ScrollView {
                        Text(String((item.text ?? "").prefix(20_000)))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                case .image:
                    if let url = store.imageURL(item), let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyStateView(text: "画像ファイルが見つかりません")
                    }
                case .file:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.fileURLs, id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(nsImage: IconCache.shared.icon(path: url.path)).resizable().frame(width: 18, height: 18)
                                    Text(url.path).font(.system(size: 12)).lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 3) {
                meta("種類", item.kind == .text ? "テキスト" : item.kind == .image ? "画像" : "ファイル")
                if let app = item.sourceApp { meta("コピー元", appName(app)) }
                meta("コピー日時", Self.dateFormatter.string(from: item.lastCopiedAt))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func meta(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).lineLimit(1)
        }
        .font(.system(size: 11))
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// 一覧用の縮小画像。元画像を毎回読み込むと重いので URL 単位でキャッシュする
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(_ url: URL) -> NSImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: .zero)
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}
