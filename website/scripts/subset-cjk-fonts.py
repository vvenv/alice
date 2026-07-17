#!/usr/bin/env python3
"""Regenerate glyph-subsetted Noto SC woff2 files for the marketing site.

Scrapes CJK characters from website sources, then downloads page-specific
subsets from Google Fonts (build-time only) into public/fonts/.
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
OUT = ROOT / "public" / "fonts"
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

CJK_RE = re.compile(
    r"["
    r"\u3000-\u303F"  # CJK punctuation
    r"\u3400-\u4DBF"  # CJK ext A
    r"\u4E00-\u9FFF"  # CJK unified
    r"\uFF00-\uFFEF"  # fullwidth
    r"·—、。，《》「」『』：；？！…“”‘’（）【】"
    r"]"
)

JOBS = [
    ("Noto+Serif+SC", ["400", "700"], "noto-serif-sc"),
    ("Noto+Sans+SC", ["400", "500", "700"], "noto-sans-sc"),
]


def collect_chars() -> str:
    chars: set[str] = set()
    paths = list(SRC.rglob("*")) + [ROOT / "index.html"]
    for path in paths:
        if not path.is_file():
            continue
        if path.suffix not in {".tsx", ".ts", ".css", ".html", ".jsx", ".js", ".json"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        chars.update(CJK_RE.findall(text))
    return "".join(sorted(chars))


def download_weight(family: str, weight: str, chars: str) -> bytes:
    css_url = (
        f"https://fonts.googleapis.com/css2?family={family}:wght@{weight}"
        f"&display=swap&text={urllib.parse.quote(chars)}"
    )
    req = urllib.request.Request(css_url, headers={"User-Agent": UA})
    css = urllib.request.urlopen(req, timeout=60).read().decode("utf-8")
    match = re.search(r"url\((https://[^)]+)\)", css)
    if not match:
        raise RuntimeError(f"No font URL in CSS for {family} {weight}")
    font_req = urllib.request.Request(match.group(1), headers={"User-Agent": UA})
    return urllib.request.urlopen(font_req, timeout=120).read()


def main() -> None:
    chars = collect_chars()
    print(f"unique CJK glyphs: {len(chars)}")
    OUT.mkdir(parents=True, exist_ok=True)

    for family, weights, slug in JOBS:
        for weight in weights:
            data = download_weight(family, weight, chars)
            dest = OUT / f"{slug}-{weight}.woff2"
            dest.write_bytes(data)
            digest = hashlib.md5(data).hexdigest()[:8]
            print(f"{dest.name}: {len(data):,} bytes  md5={digest}")


if __name__ == "__main__":
    main()
