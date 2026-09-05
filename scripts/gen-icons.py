#!/usr/bin/env python3
"""从 assets/icons 里的源图生成三个平台的应用图标。

`flutter create` 铺的是 Flutter 自带的蓝色 F 图标，得整套换掉。`icon.svg` /
`adaptive-icon.svg` 是设计源文件，同名的 png 是它们的 1024×1024 导出，这个脚本
从 png 出发。生成规则沿用 expo prebuild 当年的那套，图标与老版本保持一致。

    python3 scripts/gen-icons.py

产物（都要提交进仓库）：

    android/app/src/main/res/mipmap-<density>/ic_launcher.webp
                                             ic_launcher_round.webp
                                             ic_launcher_foreground.webp
    android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
                                              ic_launcher_round.xml
    android/app/src/main/res/values/colors.xml
    ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
    web/favicon.png
    web/icons/Icon-{192,512}.png、Icon-maskable-{192,512}.png

只在图标本身变了的时候跑。`scripts/bootstrap.sh` 不调它 —— 那个脚本只保证
`flutter create` 铺回来的 Flutter 默认图标被清掉，不引入 Pillow 依赖。

依赖：Pillow（`pip install pillow`）。webp 编码走 Pillow 自带的，不需要 cwebp。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - 只在缺依赖时走到
    sys.exit("需要 Pillow：pip install pillow")

ROOT = Path(__file__).resolve().parent.parent

SRC_ICON = ROOT / "assets/icons/icon.png"
SRC_ADAPTIVE = ROOT / "assets/icons/adaptive-icon.png"

# 自适应图标的背景色。与 assets/icons/*.svg 里的底色一致。
ICON_BACKGROUND = "#1A2B4A"

# 传统图标 48dp、自适应前景 108dp，各密度的像素尺寸。
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/iconBackground"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""

COLORS_XML = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
  <!-- 自适应图标的背景色，与 RN 版一致 -->
  <color name="iconBackground">{ICON_BACKGROUND}</color>
</resources>
"""


def resized(src: Image.Image, size: int) -> Image.Image:
    return src.resize((size, size), Image.LANCZOS)


def circular(src: Image.Image) -> Image.Image:
    """圆形裁切，用于 Android 7.1 的 ic_launcher_round。"""
    out = src.convert("RGBA")
    mask = Image.new("L", out.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, out.size[0] - 1, out.size[1] - 1), fill=255)
    out.putalpha(mask)
    return out


def write(image: Image.Image, path: Path, **kwargs) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, **kwargs)
    print(f"  {path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}")


def gen_android(icon: Image.Image, adaptive: Image.Image) -> None:
    print("Android:")
    res = ROOT / "android/app/src/main/res"

    for density, (legacy_px, foreground_px) in DENSITIES.items():
        mipmap = res / f"mipmap-{density}"
        square = resized(icon, legacy_px).convert("RGBA")
        write(square, mipmap / "ic_launcher.webp", format="WEBP", lossless=True)
        write(
            circular(square),
            mipmap / "ic_launcher_round.webp",
            format="WEBP",
            lossless=True,
        )
        write(
            resized(adaptive, foreground_px),
            mipmap / "ic_launcher_foreground.webp",
            format="WEBP",
            lossless=True,
        )

        # flutter create 铺的默认图标是 .png，与上面的 .webp 同名不同扩展名，
        # 留着会让 AGP 报 duplicate resource。
        stale = mipmap / "ic_launcher.png"
        if stale.exists():
            stale.unlink()
            print(f"  删除 {stale.relative_to(ROOT)}（Flutter 默认图标）")

    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = res / "mipmap-anydpi-v26" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(ADAPTIVE_XML, encoding="utf-8")
        print(f"  {path.relative_to(ROOT)}")

    colors = res / "values/colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(COLORS_XML, encoding="utf-8")
    print(f"  {colors.relative_to(ROOT)}")


def gen_ios(icon: Image.Image) -> None:
    print("iOS:")
    appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((appicon / "Contents.json").read_text(encoding="utf-8"))

    # iOS 图标不能带 alpha，否则上传 App Store 会被拒。
    opaque = icon.convert("RGB")

    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        write(resized(opaque, round(base * scale)), appicon / filename)


def gen_web(icon: Image.Image, adaptive: Image.Image) -> None:
    print("Web:")
    web = ROOT / "web"
    opaque = icon.convert("RGB")

    write(resized(opaque, 16), web / "favicon.png")
    for size in (192, 512):
        write(resized(opaque, size), web / f"icons/Icon-{size}.png")
        # maskable 图标会被浏览器裁成各种形状，用留白更多的自适应前景。
        write(resized(adaptive, size), web / f"icons/Icon-maskable-{size}.png")


def main() -> None:
    for src in (SRC_ICON, SRC_ADAPTIVE):
        if not src.exists():
            sys.exit(f"找不到源图 {src}")

    icon = Image.open(SRC_ICON)
    adaptive = Image.open(SRC_ADAPTIVE).convert("RGBA")

    gen_android(icon, adaptive)
    gen_ios(icon)
    gen_web(icon, adaptive)

    print("\n完成。记得把生成的图标一起提交。")


if __name__ == "__main__":
    main()
