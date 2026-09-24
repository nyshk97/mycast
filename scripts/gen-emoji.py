#!/usr/bin/env python3
"""Unicode の emoji-test.txt と CLDR の annotations（英語・日本語）から Sources/Resources/emoji.json を作る。

- 対象は fully-qualified の絵文字。肌の色のバリエーション（U+1F3FB〜1F3FF を含むもの）と Component グループは除く
- 並びは emoji-test.txt の順（= 絵文字パレットの標準の並び）
- 版は下の定数で pin する。上げたら `mise run emoji` で作り直してコミットする
- ライセンスは LICENSE-THIRD-PARTY（Unicode License v3）
"""
import json
import pathlib
import urllib.request

EMOJI_VERSION = "16.0"
CLDR_VERSION = "48.2.0"

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources" / "Resources" / "emoji.json"

EMOJI_TEST = f"https://unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt"
CLDR = "https://cdn.jsdelivr.net/npm/{pkg}@{ver}/{kind}/{lang}/annotations.json"

SKIN_TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def annotations(lang: str) -> dict:
    merged: dict = {}
    for pkg, kind in (("cldr-annotations-full", "annotations"), ("cldr-annotations-derived-full", "annotationsDerived")):
        data = json.loads(fetch(CLDR.format(pkg=pkg, ver=CLDR_VERSION, kind=kind, lang=lang)))
        merged.update(data[kind]["annotations"])
    return merged


def lookup(table: dict, emoji: str):
    # CLDR のキーは異体字セレクタ（U+FE0F）無しのことがある
    return table.get(emoji) or table.get(emoji.replace("️", ""))


def main() -> None:
    en = annotations("en")
    ja = annotations("ja")
    entries = []
    group = ""
    for line in fetch(EMOJI_TEST).decode("utf-8").splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if not line or line.startswith("#") or "; fully-qualified" not in line:
            continue
        if group == "Component":
            continue
        codepoints, rest = line.split(";", 1)
        emoji = "".join(chr(int(c, 16)) for c in codepoints.split())
        if any(ch in SKIN_TONES for ch in emoji):
            continue
        # 行末は "# 😀 E1.0 grinning face"
        name = rest.split("#", 1)[1].strip().split(" ", 2)[2]
        a_en = lookup(en, emoji) or {}
        a_ja = lookup(ja, emoji) or {}
        ja_name = (a_ja.get("tts") or [None])[0]
        keywords = []
        for k in (a_en.get("default") or []) + (a_ja.get("default") or []) + ([ja_name] if ja_name else []):
            if k and k not in keywords and k.lower() != name.lower():
                keywords.append(k)
        entry = {"e": emoji, "n": name, "k": keywords, "g": group}
        if ja_name:
            entry["j"] = ja_name
        entries.append(entry)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"OK: {OUT.relative_to(ROOT)} ({len(entries)} 件, emoji {EMOJI_VERSION} / CLDR {CLDR_VERSION})")


if __name__ == "__main__":
    main()
