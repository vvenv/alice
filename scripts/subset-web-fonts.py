#!/usr/bin/env python3
"""为 Flutter Web 生成思源宋体子集。

全量 Noto Serif SC 每个字重约 14MB，打进 Web 产物后首屏不可用。Android / iOS
仍用 pubspec.yaml 里的全量 TTF。Web 发版时用本脚本产物替换 build/web 里同名文件。

收集范围：lib/**/*.dart 源码里的字面 + assets/data/*.json（词库与词典释义）。
这样 UI 文案和离线释义都不会变成豆腐块。

    python3 scripts/subset-web-fonts.py
    pnpm fonts:subset

依赖：fonttools（`pip install fonttools`）。
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from fontTools.subset import Subsetter, Options, load_font, save_font
except ImportError:  # pragma: no cover
    sys.exit("需要 fonttools：pip install fonttools")

ROOT = Path(__file__).resolve().parent.parent
SRC_FONTS = ROOT / "assets" / "fonts"
OUT_DIR = ROOT / "assets" / "fonts" / "web"
CHARSET_PATH = OUT_DIR / "charset.txt"
FACES = (
    "NotoSerifSC_500Medium.ttf",
    "NotoSerifSC_700Bold.ttf",
)


def collect_text() -> str:
    chars: set[str] = set()
    # 基本拉丁 + 常用标点，避免子集丢掉 ASCII。
    chars.update(chr(i) for i in range(0x20, 0x7F))
    extra = (
        "、。，；：？！「」『』【】（）《》…—·"
        "“”‘’￥℃±×÷"
    )
    chars.update(extra)

    for path in (ROOT / "lib").rglob("*.dart"):
        chars.update(path.read_text(encoding="utf-8"))

    data_dir = ROOT / "assets" / "data"
    if data_dir.exists():
        for path in data_dir.glob("*.json"):
            chars.update(path.read_text(encoding="utf-8"))

    # 去掉控制字符，保留换行以外的可印刷内容。
    printable = "".join(
        c for c in sorted(chars) if c == "\n" or (c.isprintable() and c != "\ufffd")
    )
    return printable


def subset_face(name: str, text: str) -> None:
    src = SRC_FONTS / name
    if not src.exists():
        sys.exit(f"找不到源字体 {src}")
    dest = OUT_DIR / name
    options = Options()
    options.desubroutinize = True
    options.hinting = False
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recommended_glyphs = True
    font = load_font(str(src), options)
    subsetter = Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    save_font(font, str(dest), options)
    font.close()
    src_kb = src.stat().st_size / 1024
    dest_kb = dest.stat().st_size / 1024
    print(f"  {name}: {src_kb:.0f} KB → {dest_kb:.0f} KB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print("▶ Collecting charset…")
    text = collect_text()
    CHARSET_PATH.write_text(text, encoding="utf-8")
    print(f"  unique chars: {len(text)}")
    print("▶ Subsetting Noto Serif SC…")
    for name in FACES:
        subset_face(name, text)
    print(f"✓ wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
