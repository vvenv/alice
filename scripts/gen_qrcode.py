#!/usr/bin/env python3
"""Generate the download QR code for the Alice website.

Encodes https://alice.edao.plus/#download so the same QR code stays valid for
every release — the page always points to the latest APK, so the QR never needs
regenerating between builds.

Requirements: pip install qrcode[pil]   (Pillow is used for PNG output)
"""

from pathlib import Path

import qrcode

URL = "https://alice.edao.plus/#download"
# ink (#1A2B4A) — matches the website's primary text/brand color; high
# contrast on white, reliably scannable by phone cameras.
INK = "#1A2B4A"
OUT = Path(__file__).resolve().parent.parent / "website" / "public" / "qr-code.png"


def main() -> None:
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(URL)
    qr.make(fit=True)

    img = qr.make_image(fill_color=INK, back_color="white")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"QR code saved to {OUT} ({OUT.stat().st_size} bytes) -> {URL}")


if __name__ == "__main__":
    main()
