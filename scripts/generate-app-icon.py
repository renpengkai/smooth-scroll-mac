#!/usr/bin/env python3
"""Regenerate Packaging/AppIcon.appiconset PNGs (requires Pillow)."""
from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "Packaging" / "AppIcon.appiconset"

SIZES = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
]


def draw_icon(px: int) -> Image.Image:
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    margin = px * 0.08
    r = px * 0.22
    box = [margin, margin, px - margin, px - margin]
    top = (58, 120, 255)
    bot = (88, 72, 220)
    for y in range(int(box[1]), int(box[3])):
        t = (y - box[1]) / max(1, box[3] - box[1])
        col = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
        d.line([(box[0] + r, y), (box[2] - r, y)], fill=col + (255,))
    mask = Image.new("L", (px, px), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(box, radius=r, fill=255)
    bg = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    bg.paste(img, mask=mask)
    img = bg
    d = ImageDraw.Draw(img)

    cx, cy = px * 0.5, px * 0.52
    mw, mh = px * 0.28, px * 0.38
    mx0, my0 = cx - mw / 2, cy - mh / 2 + px * 0.04
    d.rounded_rectangle(
        [mx0, my0, mx0 + mw, my0 + mh], radius=mw * 0.45, fill=(255, 255, 255, 245)
    )
    d.rounded_rectangle(
        [cx - mw * 0.08, my0 + mh * 0.18, cx + mw * 0.08, my0 + mh * 0.32],
        radius=mw * 0.06,
        fill=(120, 140, 200, 255),
    )
    sw = max(2, px * 0.018)
    for sign in (-1, 1):
        ox = cx + sign * mw * 0.55
        for i, phase in enumerate([0, 0.6]):
            points = []
            for t in range(0, 101, 5):
                tt = t / 100
                y = cy - px * 0.12 + tt * px * 0.28 + phase * px * 0.06
                x = ox + sign * px * 0.06 * math.sin(tt * math.pi * 2)
                points.append((x, y))
            d.line(points, fill=(255, 255, 255, 200 - i * 40), width=int(sw))

    return img


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for size, scale in SIZES:
        px = size * scale
        suffix = "@2x" if scale == 2 else ""
        name = f"icon_{size}x{size}{suffix}.png"
        # iconutil 对带 alpha 的 PNG 有时会报 Invalid Iconset, 压成不透明 RGB
        icon = draw_icon(px)
        flat = Image.new("RGB", (px, px), (58, 120, 255))
        flat.paste(icon, mask=icon.split()[3])
        flat.save(ROOT / name, format="PNG")
        print(name, px)


if __name__ == "__main__":
    main()
