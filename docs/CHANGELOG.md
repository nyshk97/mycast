# Changelog

mycast の更新履歴。形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) ベース、バージョニングは [SemVer](https://semver.org/lang/ja/)。

`scripts/release.sh` が `[Unreleased]` を `[X.Y.Z] - YYYY-MM-DD` に切り出し、そのセクションを GitHub Release のノートと Sparkle の更新ダイアログ（appcast の `<description>`）の両方に流し込む。ここが唯一の源。

## 書き方

リリース時に Claude Code のセッションが `git log <前回タグ>..HEAD` を読んで `[Unreleased]` を埋め、commit してから `mise run release` を叩く。コミットごとには書かない。ここを読んだだけで書ける粒度で書いてある。

### 1. フォーマット

```markdown
## [Unreleased]

### ✨ Added
- メニューに「アップデートを確認…」を追加

### 🐛 Fixed
- 貼り付け後に元のアプリへ戻らないことがあるのを修正
```

- 1 項目 = 1 行。継続行は書かない（HTML 変換が `- ` 始まりの単一行しか拾わない）
- インライン Markdown は `` `code` ``・`**strong**`・`[label](url)` のみ
- 体言止め（「〜を追加」「〜を修正」「〜に変更」）。主語は書かない

### 2. カテゴリ

```
✨ Added       — 新しい機能・メニュー項目・設定キー
📝 Changed     — 既存機能の挙動・既定値・設定ファイルの書式の変更
🐛 Fixed       — 期待通りに動かなかったものが直った
🗑️ Removed     — 機能・設定キーの削除
```

使わないカテゴリの見出しは書かない。

### 3. 書くもの・書かないもの

- **書く**: ユーザーが目で見て・触って気づく変更だけ（ランチャー・クリップボード履歴・絵文字の挙動、ホットキー、メニュー）
- **書かない**: 内部リファクタ・テスト・ドキュメント・ビルド/リリーススクリプト・CI・依存の更新
- dev 版（mycast Dev）にしか影響しない変更も書かない
- 該当するものが無いリリース（配布基盤だけの修正など）は「- 内部的な変更のみ」と 1 行書く

## [Unreleased]

## [0.1.1] - 2026-09-24

### ✨ Added
- 絵文字ピッカーで ⌃F / ⌃B による左右移動

## [0.1.0] - 2026-09-24

### ✨ Added
- アプリ・システム設定のパネルを検索して開くランチャー（⌃L）
- クリップボード履歴（`c`）。テキスト・画像・ファイルを 3 か月保存し、Enter で貼り付け・⌘Enter でコピー
- 絵文字の検索と貼り付け（`e` または ⌃⌘Space）。英語・日本語のキーワードで引ける
- ルート検索に打った式の計算。Enter で答えをコピー
- ルート検索からのシステム操作（Sleep・Lock Screen・Restart・Shut Down・Close All Apps）。Restart・Shut Down・Close All Apps は Enter 2 回で実行
