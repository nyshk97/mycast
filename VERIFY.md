# 動作確認手順

## ビルドとテスト

```bash
mise run build     # Debug（mycast Dev）。署名 xcconfig が無ければ ad-hoc で通る
mise run test      # Sources/Core の純粋関数（あいまい一致・順位・履歴の判定・絵文字検索・計算）
mise run run       # /Applications/mycast Dev.app に置いて起動し直す（旧プロセスの終了を待つ）
```

ログは `~/Library/Logs/mycast/mycast-dev.log`（常用版は `mycast.log`）。先頭の語がイベント名:
`launch` / `db.migrated to vN` / `index.apps_updated` / `hotkey.registered` / `hotkey.register_failed` /
`panel.shown` / `panel.closed reason=…` / `panel.focus_failed` / `clipboard.recorded` / `clipboard.purged` / `paste.posted` /
`paste.fallback_copy reason=…` / `launch.app` / `launch.pane` / `calc.copied` /
`system.armed` / `system.sent` / `system.failed` / `system.quit_all` / `system.dry_run` / `system.permission_unchecked`。

## 検証フック（dev 版のみ・フォーカスを奪わない）

常駐中の dev に、バイナリを直接起動して引数を渡す（2 個目のプロセスは引数を既存インスタンスへ転送して終了する）。
`--show` はパネルを出すだけで、アクティブ化も入力ソースの切り替えもしない＝作業中のユーザーの邪魔をしない。
`--key enter` はシステム操作の行だけを受け付け、実行は dry run（`system.dry_run` をログに出すだけ）。
貼り付け・アプリ起動の Enter は撃てない（他のアプリに作用してしまうため。`hook.enter_refused` になる）。

```bash
B="/Applications/mycast Dev.app/Contents/MacOS/mycast Dev"
"$B" --show root --query term --dump --snapshot /tmp/s.png --hide
"$B" --show clipboard --key down --snapshot /tmp/c.png --hide
"$B" --show emoji --query いいね --dump --hide
"$B" --show root --query "3 + (34 *2)" --dump --snapshot /tmp/calc.png --hide   # items の先頭が "= 71 [Calculator]"
# 確認待ち → 検索語を変えると解除 → 2 回で dry run。ログが armed, armed, dry_run の順になる
"$B" --show root --query restart --key enter --query restar --key enter --key enter
"$B" --show root --query shut --key enter --snapshot /tmp/armed.png --hide   # 行が「Press ↵ again to Shut Down」
tail ~/Library/Logs/mycast/mycast-dev.log   # hook.dump に mode / query / selection / count / 先頭 10 件
```

- `--snapshot` はプロセス内描画なので画面収録の許可が要らない。背景のぼかしは写らない（撮影中だけ不透明にする）ので、**レイアウト確認用**
- `--key` は `down|up|left|right|escape|enter`

## 移行（スキーマ変更）の検証

使い捨てのデータディレクトリは移行を通らないので、**旧スキーマの fixture を置いてから起動する**。
`MYCAST_DATA_DIR` で dev のデータ置き場を差し替えられる（dev 版のみ）。

```bash
FX=$(mktemp -d)
sqlite3 $FX/mycast.sqlite <<'EOF'
CREATE TABLE usage (key TEXT PRIMARY KEY, count INTEGER NOT NULL, last_used REAL NOT NULL);
CREATE TABLE app_cache (path TEXT PRIMARY KEY, name TEXT NOT NULL, english TEXT NOT NULL);
INSERT INTO usage VALUES('emoji:🎉', 3, strftime('%s','now'));
PRAGMA user_version = 1;
EOF
pkill -x "mycast Dev"; while pgrep -x "mycast Dev" >/dev/null; do sleep 0.2; done
open -g --env MYCAST_DATA_DIR=$FX "/Applications/mycast Dev.app"
# ログに db.migrated to v2 だけが出る・usage の行が残る・user_version が最新になる
# 同じ fixture でもう一度起動して db.migrated が出ない（冪等）ことも見る
```

保存期間（3 か月）の削除は、`last_copied_at` を 100 日前にした行と、どの行からも参照されない画像を
fixture に入れて起動し直すと `clipboard.purged rows=1 files=1` になる。

**履歴の検証で `NSPasteboard` に書かない**（ユーザーのクリップボードを上書きする）。fixture の DB に行を直接入れる。

## 人が確認するもの（合成イベントでは確かめない）

- ⌃L（dev は ⌃⌥L）でパネルが**主画面**に出る。1 画面・2 画面（内蔵 + Studio Display）の両方
- 日本語入力中に開いても 1 打目から英字になる。Esc で閉じた後、元のアプリが日本語入力に戻る
- 他のアプリをクリックして閉じたとき、そのアプリが前面のまま（元のアプリに戻らない）
- `c` → Enter → 履歴で Enter → 元のアプリに貼り付く。⌘Enter はコピーだけで元のアプリに戻る
- `3 + (34 *2)` → Enter で `71` がコピーされ、元のアプリに戻る（貼り付けはしない）
- `e` → Enter、または ⌃⌘Space（dev は ⌃⌥⌘Space）→ 絵文字を Enter で貼り付け
- アクセシビリティ許可が無いとき・パスワード入力中は、コピーだけになりトーストが出る
- システム操作の本物の実行（dry run では撃たない）: Lock Screen・Sleep はそのまま、Restart・Shut Down は作業を保存してから。
  常用版（Hardened Runtime）で `system.failed` が出ないこと（出たら entitlement か Apple Event の許可）
- Close All Apps: Finder と mycast が残り、未保存の書類があるアプリは保存確認で止まる
- 常用版: 再ログイン後もログイン項目として常駐し、⌃L が効く

## dev と常用の併存

- 常用: `/Applications/mycast.app`（`io.github.nyshk97.mycast` / ⌃L・⌃⌘Space / データ `~/Library/Application Support/mycast/`）
- dev: `/Applications/mycast Dev.app`（`io.github.nyshk97.mycast.dev` / ⌃⌥L・⌃⌥⌘Space / データ `mycast-dev/`）
- bundle id・ホットキー・データが別なので同時に動かせる。ただし両方がクリップボードを記録する
